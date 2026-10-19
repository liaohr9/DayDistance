import Darwin
import Foundation

/// Private same-user IPC. No TCP port and no extra sandbox entitlement.
enum AutomationChannel {
  static let requestLimit = 65_536
  static let responseLimit = 2_097_152
  static func directory(bundle: Bundle = .main) -> URL {
    let key = JSONValue.digest(Data((bundle.bundleIdentifier ?? "daydistance").utf8)).prefix(10)
    return FileManager.default.temporaryDirectory.appendingPathComponent(
      "dd-api-" + key, isDirectory: true)
  }
  static func prepare(_ directory: URL) throws {
    try FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    var value = stat()
    guard lstat(directory.path, &value) == 0, (value.st_mode & S_IFMT) == S_IFDIR,
      value.st_uid == getuid(), value.st_mode & 0o077 == 0
    else {
      throw AutomationFailure("UNAVAILABLE", "The private automation directory is not secure.")
    }
  }
  static func address(_ path: String) throws -> sockaddr_un {
    var a = sockaddr_un()
    a.sun_family = sa_family_t(AF_UNIX)
    let bytes = Array(path.utf8CString)
    guard bytes.count <= MemoryLayout.size(ofValue: a.sun_path) else {
      throw AutomationFailure("UNAVAILABLE", "The automation socket path exceeds the macOS limit.")
    }
    a.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
    withUnsafeMutableBytes(of: &a.sun_path) { target in
      bytes.withUnsafeBytes { target.copyMemory(from: $0) }
    }
    return a
  }
  static func configure(_ fd: Int32) {
    _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
    var flag: Int32 = 1
    _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &flag, socklen_t(MemoryLayout.size(ofValue: flag)))
    var timeout = timeval(tv_sec: 8, tv_usec: 0)
    _ = setsockopt(
      fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout)))
    _ = setsockopt(
      fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout.size(ofValue: timeout)))
  }
  static func readLine(_ fd: Int32, limit: Int) throws -> Data {
    var result = Data()
    var bytes = [UInt8](repeating: 0, count: 4096)
    while result.count <= limit {
      let count = Darwin.read(fd, &bytes, bytes.count)
      if count < 0 && errno == EINTR { continue }
      guard count > 0 else {
        throw AutomationFailure("UNAVAILABLE", "The automation connection closed or timed out.")
      }
      if let index = bytes[..<count].firstIndex(of: 10) {
        result.append(contentsOf: bytes[..<index])
        guard result.count <= limit else { break }
        return result
      }
      result.append(contentsOf: bytes[..<count])
    }
    throw AutomationFailure("TOO_LARGE", "Automation message size limit exceeded.")
  }
  static func writeLine(_ data: Data, to fd: Int32) throws {
    var line = data
    line.append(10)
    try line.withUnsafeBytes { raw in
      var count = 0
      while count < raw.count {
        let sent = Darwin.write(fd, raw.baseAddress!.advanced(by: count), raw.count - count)
        if sent < 0 && errno == EINTR { continue }
        guard sent > 0 else {
          throw AutomationFailure("UNAVAILABLE", "The automation connection could not be written.")
        }
        count += sent
      }
    }
  }
  static func request(_ request: AutomationRequest, directory: URL) throws -> JSONValue? {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else {
      throw AutomationFailure("UNAVAILABLE", "Could not create the automation connection.")
    }
    defer { close(fd) }
    configure(fd)
    var a = try address(directory.appendingPathComponent("rpc").path)
    let result = withUnsafePointer(to: &a) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
      }
    }
    if result != 0 {
      if [ENOENT, ECONNREFUSED].contains(errno) { return nil }
      throw AutomationFailure("UNAVAILABLE", "The automation service cannot be reached.")
    }
    var uid: uid_t = 0
    var gid: gid_t = 0
    guard getpeereid(fd, &uid, &gid) == 0, uid == getuid() else {
      throw AutomationFailure("UNAVAILABLE", "The automation service has a different owner.")
    }
    let bytes = try JSONEncoder().encode(request)
    guard bytes.count <= requestLimit else {
      throw AutomationFailure("TOO_LARGE", "Request limit: 64 KiB.")
    }
    try writeLine(bytes, to: fd)
    return try JSONDecoder().decode(JSONValue.self, from: readLine(fd, limit: responseLimit))
  }
}
final class AutomationLease {
  private let fd: Int32
  private init(_ fd: Int32) { self.fd = fd }
  static func acquire(in directory: URL) throws -> AutomationLease? {
    try AutomationChannel.prepare(directory)
    let fd = Darwin.open(
      directory.appendingPathComponent("owner.lock").path,
      O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, 0o600)
    guard fd >= 0 else {
      throw AutomationFailure("UNAVAILABLE", "Cannot acquire automation ownership.")
    }
    var info = stat()
    guard fstat(fd, &info) == 0, info.st_uid == getuid(), (info.st_mode & S_IFMT) == S_IFREG,
      info.st_nlink == 1
    else {
      close(fd)
      throw AutomationFailure("UNAVAILABLE", "Invalid automation ownership file.")
    }
    guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
      let code = errno
      close(fd)
      if code == EWOULDBLOCK { return nil }
      throw AutomationFailure("UNAVAILABLE", "Cannot lock automation ownership.")
    }
    return AutomationLease(fd)
  }
  deinit {
    flock(fd, LOCK_UN)
    close(fd)
  }
}
final class AutomationSocketServer: @unchecked Sendable {
  private let source: DispatchSourceRead
  private let endpoint: URL
  private let permits = DispatchSemaphore(value: 8)
  init(directory: URL, handler: @escaping @Sendable (AutomationRequest) async -> JSONValue) throws {
    endpoint = directory.appendingPathComponent("rpc")
    var old = stat()
    if lstat(endpoint.path, &old) == 0 {
      guard (old.st_mode & S_IFMT) == S_IFSOCK, old.st_uid == getuid() else {
        throw AutomationFailure("UNAVAILABLE", "Unexpected file at automation endpoint.")
      }
      guard unlink(endpoint.path) == 0 else {
        throw AutomationFailure("UNAVAILABLE", "Cannot replace the stale automation endpoint.")
      }
    }
    var address = try AutomationChannel.address(endpoint.path)
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else {
      throw AutomationFailure("UNAVAILABLE", "Cannot create the automation listener.")
    }
    AutomationChannel.configure(fd)
    let bound = withUnsafePointer(to: &address) {
      $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
        Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
      }
    }
    guard bound == 0, listen(fd, 8) == 0 else {
      close(fd)
      throw AutomationFailure("UNAVAILABLE", "Cannot start the private automation listener.")
    }
    _ = chmod(endpoint.path, 0o600)
    _ = fcntl(fd, F_SETFL, O_NONBLOCK)
    source = DispatchSource.makeReadSource(
      fileDescriptor: fd, queue: DispatchQueue(label: "daydistance.automation.accept"))
    let permits = self.permits
    source.setEventHandler {
      while true {
        let client = accept(fd, nil, nil)
        if client < 0 { return }
        guard permits.wait(timeout: .now()) == .success else {
          close(client)
          continue
        }
        AutomationChannel.configure(client)
        _ = fcntl(client, F_SETFL, 0)
        DispatchQueue.global(qos: .utility).async {
          var uid: uid_t = 0
          var gid: gid_t = 0
          guard getpeereid(client, &uid, &gid) == 0, uid == getuid() else {
            close(client)
            permits.signal()
            return
          }
          do {
            let request = try JSONDecoder().decode(
              AutomationRequest.self,
              from: AutomationChannel.readLine(client, limit: AutomationChannel.requestLimit))
            Task {
              let response = await handler(request)
              DispatchQueue.global(qos: .utility).async {
                defer {
                  close(client)
                  permits.signal()
                }
                if let data = try? response.encoded(), data.count <= AutomationChannel.responseLimit
                {
                  try? AutomationChannel.writeLine(data, to: client)
                } else {
                  try? AutomationChannel.writeLine(
                    AutomationFailure(
                      "TOO_LARGE", "Use list pagination to reduce the response size."
                    ).response.encoded(), to: client)
                }
              }
            }
          } catch {
            try? AutomationChannel.writeLine(
              AutomationFailure("INVALID_REQUEST", "Expected a bounded JSON API request.").response
                .encoded(), to: client)
            close(client)
            permits.signal()
          }
        }
      }
    }
    source.setCancelHandler { close(fd) }
    source.resume()
  }
  deinit {
    source.cancel()
    unlink(endpoint.path)
  }
}
