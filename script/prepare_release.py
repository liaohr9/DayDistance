#!/usr/bin/env python3
"""Read-only Developer ID release gate; never signs or uploads."""
import argparse
import base64
import json
import os
from pathlib import Path
import plistlib
import re
import subprocess
import tempfile
import zipfile

IDENTIFIERS = ["local.daydistance.mac", "local.daydistance.mac.widget"]
SPARKLE_BASE = "Contents/Frameworks/Sparkle.framework/Versions/B/"
SPARKLE_CODE = [SPARKLE_BASE + path for path in ["Sparkle", "Autoupdate", "Updater.app/Contents/MacOS/Updater", "XPCServices/Installer.xpc/Contents/MacOS/Installer"]]
MACHO_MAGIC = {b"\xfe\xed\xfa\xce", b"\xce\xfa\xed\xfe", b"\xfe\xed\xfa\xcf", b"\xcf\xfa\xed\xfe", b"\xca\xfe\xba\xbe", b"\xbe\xba\xfe\xca", b"\xca\xfe\xba\xbf", b"\xbf\xba\xfe\xca"}


def evaluate(facts, team, group, stage):
    errors = []
    if not re.fullmatch(r"[A-Z0-9]{10}", team): errors.append("A real 10-character team identifier is required")
    if not group.startswith(team + ".") or not re.fullmatch(r"[A-Z0-9]{10}\.[A-Za-z0-9.-]+", group):
        errors.append("This macOS-only workflow requires a team-prefixed App Group")
    bundles = facts.get("bundles", [])
    if len(bundles) != 2: errors.append("Expected main app and exactly one widget")
    for index, bundle in enumerate(bundles):
        label = bundle.get("identifier", "unknown")
        if index >= len(IDENTIFIERS) or label != IDENTIFIERS[index]: errors.append(label + ": identifier mismatch")
        for field in ["developer_id", "runtime", "timestamp", "verified"]:
            if bundle.get(field) is not True: errors.append(label + ": " + field + " check failed")
        if bundle.get("team") != team: errors.append(label + ": team mismatch")
        if bundle.get("storage") != "shared" or bundle.get("group") != group: errors.append(label + ": shared storage/group mismatch")
        if set(bundle.get("architectures", [])) != {"arm64"}: errors.append(label + ": Apple Silicon arm64 only required")
        if bundle.get("minimum_os") != "14.0": errors.append(label + ": minimum macOS changed")
        if bundle.get("binary_minimum_os") != {"arm64": "14.0"}:
            errors.append(label + ": binary deployment targets must match macOS 14")
        for field in ["version", "build"]:
            if not bundle.get(field) or bundle.get(field) != bundles[0].get(field): errors.append(label + ": " + field + " mismatch")
        entitlements = bundle.get("entitlements", {})
        if entitlements.get("com.apple.security.app-sandbox") is not True: errors.append(label + ": sandbox required")
        selected_files = entitlements.get("com.apple.security.files.user-selected.read-write", False)
        if (index == 0 and selected_files is not True) or (index != 0 and
                (selected_files or entitlements.get("com.apple.security.files.user-selected.read-only"))):
            errors.append(label + ": user-selected file permission mismatch")
        if entitlements.get("com.apple.security.application-groups") != [group]: errors.append(label + ": entitlement group mismatch")
        allowed_mach = index == 0 and facts.get("updater", {}).get("configured") and entitlements.get("com.apple.security.temporary-exception.mach-lookup.global-name") == ["local.daydistance.mac-spks", "local.daydistance.mac-spki"]
        forbidden = [key for key in entitlements if ("temporary-exception" in key and not (allowed_mach and key == "com.apple.security.temporary-exception.mach-lookup.global-name")) or (key.startswith("com.apple.security.cs.") and entitlements[key])]
        if entitlements.get("com.apple.security.get-task-allow"): forbidden.append("com.apple.security.get-task-allow")
        if forbidden: errors.append(label + ": forbidden entitlements " + ", ".join(sorted(forbidden)))
    updater = facts.get("updater", {})
    if updater.get("required"):
        code = updater.get("code", [])
        if not updater.get("configured") or {item.get("path") for item in code} != set(SPARKLE_CODE): errors.append("Updater configuration or helper inventory mismatch")
        for item in code:
            if not all(item.get(field) for field in ["verified", "runtime", "timestamp"]) or item.get("architectures") != ["arm64"]:
                errors.append("Sparkle helper signing/runtime/architecture failed: " + item.get("path", "unknown"))
    if not facts.get("nested_valid"): errors.append("Nested code signature validation failed")
    if facts.get("unexpected_code"): errors.append("Unexpected nested code or escaping links: " + ", ".join(facts["unexpected_code"]))
    if facts.get("debug_files"): errors.append("Debug/preview binaries present: " + ", ".join(facts["debug_files"]))
    if stage == "distribution":
        if not facts.get("stapled"): errors.append("Stapled notarization ticket validation failed")
        if not facts.get("gatekeeper"): errors.append("Gatekeeper assessment failed")
    elif stage != "notarization-input": errors.append("Unknown validation stage")
    return {"status": "blocked" if errors else ("signature_and_notarization_passed" if stage == "distribution" else "ready_for_notarization"),
            "distributable": not errors and stage == "distribution", "errors": errors, "stage": stage}


def run(arguments):
    return subprocess.run(arguments, capture_output=True, timeout=60)


def inspect(app, team, stage):
    app = Path(app).resolve(strict=True)
    widget = app / "Contents/PlugIns/DayDistanceWidget.appex"
    facts = {"bundles": [], "unexpected_code": [], "debug_files": [], "stapled": False, "gatekeeper": False}
    requirement = '=anchor apple generic and certificate 1[field.1.2.840.113635.100.6.2.6] exists and certificate leaf[field.1.2.840.113635.100.6.1.13] exists and certificate leaf[subject.OU] = "' + team + '"'
    expected_executables = []
    for bundle in [app, widget]:
        info = plistlib.loads((bundle / "Contents/Info.plist").read_bytes())
        executable = bundle / "Contents/MacOS" / info["CFBundleExecutable"]
        if not executable.resolve().is_relative_to(app): raise ValueError("Executable escapes app")
        expected_executables.append(executable)
        architectures_result = run(["/usr/bin/lipo", "-archs", str(executable)])
        architectures = architectures_result.stdout.decode().split() if architectures_result.returncode == 0 else []
        binary_minimum_os = {}
        for arch in architectures:
            load_commands = run(["/usr/bin/otool", "-arch", arch, "-l", str(executable)])
            load_text = load_commands.stdout.decode(errors="replace")
            minimum = re.search(r"cmd LC_BUILD_VERSION\s+cmdsize \d+\s+platform (?:1|macos)\s+minos ([0-9.]+)", load_text)
            if minimum is None:
                minimum = re.search(r"cmd LC_VERSION_MIN_MACOSX\s+cmdsize \d+\s+version ([0-9.]+)", load_text)
            if load_commands.returncode == 0 and minimum: binary_minimum_os[arch] = minimum.group(1)
        signatures = []
        for arch in architectures:
            detail = run(["/usr/bin/codesign", "-dvvv", "--arch", arch, str(bundle)])
            text = (detail.stdout + detail.stderr).decode(errors="replace")
            ent = run(["/usr/bin/codesign", "-d", "--arch", arch, "--entitlements", ":-", str(bundle)])
            entitlements = plistlib.loads(ent.stdout) if ent.returncode == 0 and ent.stdout.strip() else {}
            team_match = re.search(r"^TeamIdentifier=(.+)$", text, re.MULTILINE)
            signatures.append({"team": team_match.group(1) if team_match else None, "entitlements": entitlements,
                "developer_id": detail.returncode == 0 and "Authority=Developer ID Application:" in text,
                "runtime": bool(re.search(r"flags=0x[0-9a-f]+\([^\n)]*\bruntime\b", text)),
                "timestamp": bool(re.search(r"^Timestamp=.+", text, re.MULTILINE))})
        first = signatures[0] if signatures else {}
        record = {"identifier": info.get("CFBundleIdentifier"), "version": info.get("CFBundleShortVersionString"), "build": info.get("CFBundleVersion"),
            "minimum_os": info.get("LSMinimumSystemVersion"), "storage": info.get("DayDistanceStorageMode"), "group": info.get("DayDistanceAppGroup"),
            "architectures": architectures, "binary_minimum_os": binary_minimum_os, "entitlements": first.get("entitlements", {}), "team": first.get("team")}
        for field in ["developer_id", "runtime", "timestamp"]: record[field] = bool(signatures) and all(signature[field] for signature in signatures)
        matching = all(signature["entitlements"] == first.get("entitlements") and signature["team"] == first.get("team") for signature in signatures)
        identified_requirement = requirement + ' and identifier "' + IDENTIFIERS[len(facts["bundles"])] + '"'
        record["verified"] = matching and run(["/usr/bin/codesign", "--verify", "--strict", "--all-architectures", "-R", identified_requirement, str(bundle)]).returncode == 0
        facts["bundles"].append(record)
    main_info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
    expected_bundles = {widget}
    if main_info.get("SUFeedURL"):
        try: key_valid = len(base64.b64decode(main_info.get("SUPublicEDKey", ""), validate=True)) == 32
        except (ValueError, TypeError): key_valid = False
        configured = key_valid and main_info.get("SUFeedURL") == "https://raw.githubusercontent.com/liaohr9/DayDistance/main/appcast.xml" and main_info.get("SUEnableInstallerLauncherService") is True and main_info.get("SUVerifyUpdateBeforeExtraction") is True and main_info.get("SURequireSignedFeed") is True and main_info.get("SUAllowsAutomaticUpdates") is False
        code = []
        expected_bundles |= {app / "Contents/Frameworks/Sparkle.framework", app / (SPARKLE_BASE + "Updater.app"), app / (SPARKLE_BASE + "XPCServices/Installer.xpc")}
        for relative in SPARKLE_CODE:
            binary = app / relative
            expected_executables.append(binary)
            details = run(["/usr/bin/codesign", "-dvvv", str(binary)])
            text = (details.stdout + details.stderr).decode(errors="replace")
            code.append({"path": relative, "architectures": run(["/usr/bin/lipo", "-archs", str(binary)]).stdout.decode().split(),
                "verified": run(["/usr/bin/codesign", "--verify", "--strict", "-R", requirement, str(binary)]).returncode == 0,
                "runtime": bool(re.search(r"flags=0x[0-9a-f]+\([^\n)]*\bruntime\b", text)), "timestamp": bool(re.search(r"^Timestamp=.+", text, re.MULTILINE))})
        facts["updater"] = {"required": True, "configured": configured, "code": code}
    expected_executables = {path.resolve() for path in expected_executables}
    facts["nested_valid"] = run(["/usr/bin/codesign", "--verify", "--deep", "--strict", "--all-architectures", str(app)]).returncode == 0
    for path in app.rglob("*"):
        relative = str(path.relative_to(app))
        if path.is_symlink() and not path.resolve().is_relative_to(app): facts["unexpected_code"].append(relative); continue
        if path.name.endswith(".debug.dylib") or path.name == "__preview.dylib": facts["debug_files"].append(relative)
        if path.is_file():
            with path.open("rb") as handle: magic = handle.read(4)
            if magic in MACHO_MAGIC and path.resolve() not in expected_executables: facts["unexpected_code"].append(relative)
        elif path.suffix in {".app", ".appex", ".framework", ".xpc"} and path not in expected_bundles:
            facts["unexpected_code"].append(relative)
    if stage == "distribution":
        facts["stapled"] = run(["/usr/bin/xcrun", "stapler", "validate", str(app)]).returncode == 0
        facts["gatekeeper"] = run(["/usr/sbin/spctl", "--assess", "--type", "execute", "--verbose=2", str(app)]).returncode == 0
    return facts


def checked(app, team, group, stage):
    facts = inspect(app, team, stage)
    report = evaluate(facts, team, group, stage)
    report["facts"] = facts
    return report


def archive_and_extract(app, archive, unpacked):
    result = run(["/usr/bin/ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(app), str(archive)])
    if result.returncode: raise RuntimeError("ZIP creation failed")
    with zipfile.ZipFile(archive) as zipped:
        if zipped.testzip() is not None: raise ValueError("ZIP integrity failed")
    result = run(["/usr/bin/ditto", "-x", "-k", str(archive), str(unpacked)])
    if result.returncode: raise RuntimeError("ZIP extraction failed")


def package(app, output, team, group, stage):
    app = Path(app).resolve(strict=True)
    raw_output = Path(output).absolute()
    output = raw_output.parent.resolve() / raw_output.name
    inside_source = output.is_relative_to(app) or any(ancestor.exists() and ancestor.samefile(app)
        for ancestor in [output.parent, *output.parent.parents])
    if output.suffix != ".zip" or inside_source: raise ValueError("Choose a separate .zip output")
    if output.exists() or output.is_symlink(): raise FileExistsError("Existing output is preserved")
    output.parent.mkdir(parents=True, exist_ok=True)
    # Isolate from source changes; no indexed duplicate app is retained.
    with tempfile.TemporaryDirectory(prefix="daydistance-package-", suffix=".noindex", dir=output.parent) as temporary:
        root = Path(temporary)
        staged = root / "日距.app"
        result = run(["/usr/bin/ditto", str(app), str(staged)])
        if result.returncode: raise RuntimeError("Staging copy failed")
        report = checked(staged, team, group, stage)
        if report["errors"]: raise ValueError("Staged app validation failed: " + "; ".join(report["errors"]))
        archive = root / "candidate.zip"
        unpacked = root / "unpacked.noindex"
        archive_and_extract(staged, archive, unpacked)
        report = checked(unpacked / "日距.app", team, group, stage)
        if report["errors"]: raise ValueError("Extracted ZIP validation failed: " + "; ".join(report["errors"]))
        # Same filesystem, atomic and exclusive: never overwrite an older artifact.
        os.link(archive, output)
        return str(output)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("app")
    parser.add_argument("--team", required=True)
    parser.add_argument("--group", required=True)
    parser.add_argument("--package")
    parser.add_argument("--stage", choices=["notarization-input", "distribution"], default="notarization-input")
    args = parser.parse_args()
    report = {"status": "blocked", "distributable": False, "stage": args.stage, "errors": []}
    try:
        if not re.fullmatch(r"[A-Z0-9]{10}", args.team): raise ValueError("A real 10-character team identifier is required")
        report = checked(Path(args.app), args.team, args.group, args.stage)
        if not report["errors"] and args.package: report["package"] = package(args.app, args.package, args.team, args.group, args.stage)
    except (OSError, ValueError, RuntimeError, subprocess.SubprocessError, plistlib.InvalidFileException, KeyError) as error:
        report["status"] = "blocked"; report["distributable"] = False; report["errors"].append(str(error))
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 1 if report["errors"] else 0


if __name__ == "__main__": raise SystemExit(main())
