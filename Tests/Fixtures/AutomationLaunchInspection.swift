import AppKit
import Foundation
let identity = CommandLine.arguments[1]
let apps = NSRunningApplication.runningApplications(withBundleIdentifier: identity).filter { !$0.isTerminated }.map {
    ["pid": Int($0.processIdentifier), "policy": $0.activationPolicy.rawValue, "finished": $0.isFinishedLaunching] as [String: Any]
}
print(String(data: try! JSONSerialization.data(withJSONObject: apps, options: [.sortedKeys]), encoding: .utf8)!)
