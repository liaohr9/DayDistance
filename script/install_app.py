#!/usr/bin/env python3
"""Install one canonical app without interrupting an open editing session."""
import argparse
import fcntl
import os
import plistlib
import shutil
import signal
import subprocess
import sys
import tempfile
import time
import uuid
import zipfile
from pathlib import Path

BUNDLE_ID = "local.daydistance.mac"
REGISTER = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"


def metadata(app):
    return plistlib.loads((app / "Contents/Info.plist").read_bytes())


def validate(source, destination):
    if source.is_symlink() or destination.is_symlink():
        raise ValueError("Refusing a symbolic-link application path")
    source = source.resolve()
    destination = destination.resolve()
    if source == destination or source.is_relative_to(destination) or destination.is_relative_to(source):
        raise ValueError("Candidate and installed app must be separate paths")
    main = metadata(source)
    widget = metadata(source / "Contents/PlugIns/DayDistanceWidget.appex")
    if main.get("CFBundleIdentifier") != BUNDLE_ID or widget.get("CFBundleIdentifier") != BUNDLE_ID + ".widget":
        raise ValueError("Unexpected application or widget identifier")
    for key in ("CFBundleVersion", "CFBundleShortVersionString"):
        if not main.get(key) or main.get(key) != widget.get(key):
            raise ValueError("Application and widget version mismatch")
    if destination.exists() and metadata(destination).get("CFBundleIdentifier") != BUNDLE_ID:
        raise ValueError("Refusing to overwrite another application's identifier")


class MacRuntime:
    def verify(self, app):
        subprocess.run(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(app)], check=True)
        identities = []
        for bundle in (app, app / "Contents/PlugIns/DayDistanceWidget.appex"):
            result = subprocess.run(["/usr/bin/codesign", "-dvv", str(bundle)], check=True, capture_output=True, text=True)
            values = dict(line.split("=", 1) for line in (result.stdout + result.stderr).splitlines() if "=" in line)
            team = values.get("TeamIdentifier")
            if values.get("Signature") == "adhoc": identities.append(("adhoc", None))
            elif team and team != "not set": identities.append(("team", team))
            else: raise ValueError("Unrecognized signing identity")
        if identities[0] != identities[1]:
            raise ValueError("Application and widget signing identities differ")
    def main_running(self):
        code = subprocess.run(["/usr/bin/pgrep", "-x", "DayDistance"], stdout=subprocess.DEVNULL).returncode
        if code not in (0, 1): raise RuntimeError("Unable to check application process; update deferred")
        return code == 0
    def stop_extension(self, app):
        executable = str(app / "Contents/PlugIns/DayDistanceWidget.appex/Contents/MacOS/DayDistanceWidget")
        for line in subprocess.check_output(["/bin/ps", "-axo", "pid=,comm="], text=True).splitlines():
            parts = line.strip().split(None, 1)
            if len(parts) != 2 or parts[1] != executable:
                continue
            pid = int(parts[0])
            try:
                os.kill(pid, signal.SIGTERM)
                os.kill(pid, signal.SIGCONT)
                deadline = time.monotonic() + 3
                while time.monotonic() < deadline:
                    try: os.kill(pid, 0)
                    except ProcessLookupError: break
                    time.sleep(0.05)
                else: raise RuntimeError("Old widget is still running; update deferred")
            except ProcessLookupError:
                pass
    def register(self, app):
        subprocess.run([REGISTER, "-f", str(app)], check=True)
        subprocess.run(["/usr/bin/pluginkit", "-a", str(app / "Contents/PlugIns/DayDistanceWidget.appex")], check=True)


def cleanup_registration(source, destination, runtime):
    """Xcode registers macOS products unconditionally; remove only our candidate."""
    if source.resolve() == destination.resolve():
        raise ValueError("Cannot unregister the installed application as a candidate")
    has_candidate = source.exists() and (source / "Contents/Info.plist").exists()
    if has_candidate:
        if metadata(source).get("CFBundleIdentifier") != BUNDLE_ID:
            raise ValueError("Unexpected candidate identifier")
    errors = []
    def attempt(action):
        try: action()
        except (ValueError, RuntimeError, OSError, subprocess.CalledProcessError) as error:
            errors.append(str(error))
    def unregister(args, allowed_error):
        result = subprocess.run(args, capture_output=True, text=True)
        if result.returncode and allowed_error not in result.stdout + result.stderr:
            raise RuntimeError(result.stdout + result.stderr or f"Registration command failed: {args[0]}")
    if has_candidate:
        attempt(lambda: runtime.stop_extension(source))
        widget = source / "Contents/PlugIns/DayDistanceWidget.appex"
        if widget.exists():
            attempt(lambda: unregister(["/usr/bin/pluginkit", "-r", str(widget)], "no plugin at"))
        attempt(lambda: unregister([REGISTER, "-u", str(source)], "-10814"))
    def restore_installed():
        if not destination.exists(): return
        if metadata(destination).get("CFBundleIdentifier") != BUNDLE_ID:
            raise ValueError("Unexpected installed identifier")
        runtime.verify(destination)
        runtime.register(destination)
    attempt(restore_installed)
    if errors: raise RuntimeError("; ".join(errors))


def install(source, destination, backups, runtime):
    source, destination, backups = Path(source), Path(destination), Path(backups)
    validate(source, destination)
    runtime.verify(source)
    if runtime.main_running():
        raise RuntimeError("DayDistance is running; close the app normally before installing. No changes made.")
    destination.parent.mkdir(parents=True, exist_ok=True)
    with (destination.parent / ".daydistance-install.lock").open("a") as lock:
        try: fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError: raise RuntimeError("Another install is running; update deferred")
        validate(source, destination)
        staging = Path(tempfile.mkdtemp(prefix=".daydistance-install-", suffix=".noindex", dir=destination.parent))
        candidate, previous = staging / "candidate.app", staging / "previous.app"
        backup = None
        replaced = False
        committed = False
        try:
            subprocess.run(["/usr/bin/ditto", str(source), str(candidate)], check=True)
            runtime.verify(candidate)
            if runtime.main_running():
                raise RuntimeError("DayDistance is running; update deferred")
            if destination.exists():
                backups.mkdir(parents=True, exist_ok=True)
                backup = backups / ("daydistance-previous-" + uuid.uuid4().hex + ".zip")
                subprocess.run(["/usr/bin/ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(destination), str(backup)], check=True)
                with zipfile.ZipFile(backup) as archive:
                    if archive.testzip() is not None: raise RuntimeError("Rollback archive is invalid")
            runtime.stop_extension(destination)
            if runtime.main_running():
                raise RuntimeError("DayDistance is running; update deferred")
            if destination.exists(): os.replace(destination, previous)
            try:
                os.replace(candidate, destination)
                replaced = True
                runtime.verify(destination)
                runtime.register(destination)
                committed = True
            except Exception:
                if replaced and destination.exists(): shutil.rmtree(destination)
                if previous.exists():
                    os.replace(previous, destination)
                    runtime.register(destination)
                raise
        finally:
            if previous.exists() and not committed:
                print(f"Recovery bundle preserved: {previous}", file=sys.stderr)
            else:
                shutil.rmtree(staging)
        return backup


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("--destination", type=Path, default=Path("/Applications/日距.app"))
    parser.add_argument("--backups", type=Path)
    parser.add_argument("--cleanup-registration", action="store_true")
    args = parser.parse_args()
    try:
        if args.cleanup_registration:
            cleanup_registration(args.source, args.destination, MacRuntime())
            print("Candidate unregistered; installed app remains canonical.")
            return 0
        if args.backups is None:
            parser.error("--backups is required for installation")
        backup = install(args.source, args.destination, args.backups, MacRuntime())
    except (ValueError, RuntimeError, OSError, subprocess.CalledProcessError, zipfile.BadZipFile) as error:
        print(f"Install deferred or failed: {error}", file=sys.stderr)
        return 1
    print(f"Installed: {args.destination}")
    if backup: print(f"Rollback ZIP: {backup}")
    return 0


if __name__ == "__main__": sys.exit(main())
