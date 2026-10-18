#!/usr/bin/env python3
"""Control faults only in a live disposable UI probe; never accept arbitrary data paths."""
import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile

from disk_ui_probe import fill_disk, release_space


def temporary_probe(value):
    root = Path(value).resolve(strict=True)
    if root.parent != Path(tempfile.gettempdir()).resolve() or not root.name.startswith("daydistance-ui-") or root.suffix != ".noindex":
        raise ValueError("Expected a direct child QA folder in the system temporary directory")
    info = plistlib.loads((root / "日距列表验证.app/Contents/Info.plist").read_bytes())
    if info.get("CFBundleIdentifier") != "local.daydistance.uiprobe":
        raise ValueError("Not the disposable QA host")
    data = root / "data"
    source = data / "events.json"
    lock = data / "events.json.lock"
    writer = root / "writer"
    if any(p.is_symlink() for p in (data, source, lock, writer)):
        raise ValueError("QA paths must not be symlinks")
    if not source.is_file() or not lock.is_file() or not writer.is_file():
        raise ValueError("Expected a seeded fault-mode QA host")
    return root


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("operation", choices=("rename", "busy", "read-only", "writable", "inspect", "recover", "corrupt", "newer", "fill-disk", "release-space"))
    parser.add_argument("folder")
    args = parser.parse_args()
    root = temporary_probe(args.folder)
    data = root / "data"
    source = data / "events.json"
    disk_result = None
    if args.operation == "rename":
        subprocess.run([str(root / "writer"), str(root)], check=True, stdout=subprocess.DEVNULL)
    elif args.operation == "busy":
        with (data / "events.json.lock").open("r+") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            print("Temporary write lock acquired. Press Return to release.", flush=True)
            input()
    elif args.operation in ("read-only", "writable"):
        data.chmod(0o500 if args.operation == "read-only" else 0o700)
    elif args.operation in ("fill-disk", "release-space"):
        with (data / "events.json.lock").open("r+") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            if args.operation == "fill-disk":
                disk_result = fill_disk(root)
            else:
                release_space(root)
                stat = os.statvfs(data)
                disk_result = {"available_bytes": stat.f_bavail * stat.f_frsize}
    elif args.operation in ("recover", "corrupt", "newer"):
        baseline = root / "baseline.json"
        if baseline.is_symlink() or not baseline.is_file():
            raise ValueError("Expected the QA baseline file, without symlinks")
        original = baseline.read_bytes()
        try:
            envelope = json.loads(original)
            if not isinstance(envelope, dict) or envelope.get("schemaVersion") not in (1, 2, 3, 4, 5, 6, 7) or not isinstance(envelope.get("events"), list):
                raise ValueError("Invalid QA baseline")
        except (ValueError, UnicodeDecodeError) as error:
            raise ValueError("Invalid QA baseline") from error
        if args.operation == "corrupt":
            original = b'{"schemaVersion":'
        elif args.operation == "newer":
            envelope["schemaVersion"] = 8
            original = json.dumps(envelope, ensure_ascii=False).encode("utf-8")
        with (data / "events.json.lock").open("r+") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            temporary = None
            try:
                with tempfile.NamedTemporaryFile(dir=data, prefix=".recovery-", delete=False) as output:
                    temporary = Path(output.name)
                    output.write(original)
                    output.flush()
                    os.fsync(output.fileno())
                os.replace(temporary, source)
            finally:
                if temporary is not None:
                    temporary.unlink(missing_ok=True)
    raw = source.read_bytes()
    result = {"sha256": hashlib.sha256(raw).hexdigest(), "data_mode": oct(data.stat().st_mode & 0o777)}
    try:
        envelope = json.loads(raw)
        result.update(valid_json=True, schema_version=envelope.get("schemaVersion"),
                      events=[{"id": e["id"], "title": e["title"]} for e in envelope["events"]])
    except (ValueError, UnicodeDecodeError, TypeError, KeyError, AttributeError) as error:
        result.update(valid_json=False, decode_error=str(error))
    if disk_result is not None:
        result["disk"] = disk_result
    print(json.dumps(result, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
