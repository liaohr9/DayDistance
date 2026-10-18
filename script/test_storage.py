#!/usr/bin/env python3
"""Exercise real writers and EventStore on disposable data, outside the installed app."""
import fcntl
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time


def main():
    project = Path(__file__).resolve().parent.parent
    environment = os.environ.copy()
    environment.setdefault("DEVELOPER_DIR", "/Volumes/haoran 1/Applications/Xcode.app/Contents/Developer")
    sources = [str(s.relative_to(project)) for s in sorted((project / "Shared/Core").glob("*.swift"))]
    sources += ["App/Services/EventHistoryUndoManager.swift", "Shared/Platform/SharedContainer.swift",
                "App/Stores/EventStore.swift", "Tests/Fixtures/StorageProbe.swift"]
    with tempfile.TemporaryDirectory(suffix=".noindex") as temporary:
        root = Path(temporary)
        binary = str(root / "probe")
        subprocess.run(["/usr/bin/xcrun", "swiftc", "-parse-as-library", *[str(project / s) for s in sources],
                        "-o", binary], env=environment, check=True, timeout=90)
        for round_number in range(8):
            folder = root / str(round_number)
            folder.mkdir()
            data = folder / "events.json"
            subprocess.run([binary, "seed", str(data)], check=True, timeout=10)
            children = [subprocess.Popen([binary, "race", str(data), str(i)]) for i in range(4)]
            try:
                deadline = time.monotonic() + 5
                while len(list(folder.glob("*.ready"))) != 4:
                    if time.monotonic() >= deadline: raise RuntimeError("Writer barrier timed out")
                    time.sleep(.005)
                (folder / "go").touch()
                codes = [child.wait(timeout=10) for child in children]
                assert codes.count(0) == 1 and all(c in (0, 42, 43) for c in codes), codes
                assert len(json.loads(data.read_text())["events"]) == 2
            finally:
                for child in children:
                    if child.poll() is None: child.kill()
                    child.wait()
        print("8 races / 32 writer processes: exactly one succeeds each round, no stale overwrite", flush=True)
        folder = root / "busy"
        folder.mkdir()
        data = folder / "events.json"
        subprocess.run([binary, "seed", str(data)], check=True, timeout=10)
        original = data.read_bytes()
        with open(str(data) + ".lock", "a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX)
            result = subprocess.run([binary, "write", str(data)], timeout=2)
            assert result.returncode == 43 and data.read_bytes() == original
        subprocess.run([binary, "write", str(data)], check=True, timeout=10)
        print("Cross-process busy lock: refused immediately; retry after unlock succeeds", flush=True)
        folder = root / "store"
        folder.mkdir()
        subprocess.run([binary, "store", str(folder / "events.json")], check=True, timeout=10)
        folder = root / "reload"
        folder.mkdir()
        subprocess.run([binary, "reload", str(folder / "events.json")], check=True, timeout=10)
        folder = root / "transfer"
        folder.mkdir()
        subprocess.run([binary, "transfer", str(folder / "events.json")], check=True, timeout=10)


if __name__ == "__main__": main()
