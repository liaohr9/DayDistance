#!/usr/bin/env python3
"""Release policy regressions and actual local ad hoc rejection; no credentials."""
import importlib.util
import json
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("release", Path(__file__).with_name("prepare_release.py"))
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)
TEAM = "A1B2C3D4E5"
GROUP = TEAM + ".local.daydistance.shared"


def good_facts():
    bundles = []
    for identifier in ["local.daydistance.mac", "local.daydistance.mac.widget"]:
        bundles.append({"identifier": identifier, "version": "1.3.3", "build": "7", "minimum_os": "14.0",
            "storage": "shared", "group": GROUP, "team": TEAM, "developer_id": True,
            "runtime": True, "timestamp": True, "verified": True, "architectures": ["arm64", "x86_64"],
            "binary_minimum_os": {"arm64": "14.0", "x86_64": "14.0"},
            "entitlements": {"com.apple.security.app-sandbox": True, "com.apple.security.application-groups": [GROUP]}})
    bundles[0]["entitlements"]["com.apple.security.files.user-selected.read-write"] = True
    return {"bundles": bundles, "nested_valid": True, "unexpected_code": [], "debug_files": [],
            "stapled": False, "gatekeeper": False}


class ReleaseTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # Native signed fixture, independent of the installed app and user data.
        cls.fixture_directory = tempfile.TemporaryDirectory(suffix=".noindex")
        root = Path(cls.fixture_directory.name)
        source = root / "main.c"; source.write_text("int main(void) { return 0; }\n")
        cls.app = root / "日距.app"
        for bundle, identifier in [(cls.app / "Contents/PlugIns/DayDistanceWidget.appex", release.IDENTIFIERS[1]), (cls.app, release.IDENTIFIERS[0])]:
            executable = bundle / "Contents/MacOS/Fixture"
            executable.parent.mkdir(parents=True, exist_ok=True)
            subprocess.run(["/usr/bin/xcrun", "clang", "-arch", "arm64", "-arch", "x86_64", "-mmacosx-version-min=14.0", str(source), "-o", str(executable)], check=True, capture_output=True)
            info = {"CFBundleIdentifier": identifier, "CFBundleExecutable": "Fixture", "CFBundleVersion": "7",
                    "CFBundleShortVersionString": "1.3.3", "LSMinimumSystemVersion": "14.0",
                    "DayDistanceStorageMode": "shared", "DayDistanceAppGroup": GROUP}
            (bundle / "Contents/Info.plist").write_bytes(plistlib.dumps(info))
            subprocess.run(["/usr/bin/codesign", "--force", "--sign", "-", "--options", "runtime", str(bundle)], check=True, capture_output=True)

    @classmethod
    def tearDownClass(cls):
        cls.fixture_directory.cleanup()

    def testSparkleMachLookupIsNarrowAndMainOnly(self):
        facts = good_facts()
        facts["updater"] = {"required": True, "configured": True, "code": [{"path": path, "verified": True, "runtime": True, "timestamp": True, "architectures": ["arm64", "x86_64"]} for path in release.SPARKLE_CODE]}
        ent = facts["bundles"][0]["entitlements"]
        ent["com.apple.security.network.client"] = True
        ent["com.apple.security.temporary-exception.mach-lookup.global-name"] = ["local.daydistance.mac-spks", "local.daydistance.mac-spki"]
        self.assertFalse(release.evaluate(facts, TEAM, GROUP, "notarization-input")["errors"])
        ent["com.apple.security.temporary-exception.mach-lookup.global-name"].append("other-service")
        self.assertTrue(release.evaluate(facts, TEAM, GROUP, "notarization-input")["errors"])

    def testSparkleHelpersRequireSameTeamSignatureRuntimeAndUniversal(self):
        for field, value in [("verified", False), ("runtime", False), ("timestamp", False), ("architectures", ["arm64"])]:
            facts = good_facts()
            code = [{"path": path, "verified": True, "runtime": True, "timestamp": True, "architectures": ["arm64", "x86_64"]} for path in release.SPARKLE_CODE]
            code[0][field] = value
            facts["updater"] = {"required": True, "configured": True, "code": code}
            self.assertTrue(release.evaluate(facts, TEAM, GROUP, "notarization-input")["errors"])

    def testActualDittoRoundtripPreservesNestedAdhocSignatures(self):
        with tempfile.TemporaryDirectory(suffix=".noindex") as directory:
            root = Path(directory)
            archive = root / "fixture-not-for-distribution.zip"
            unpacked = root / "unpacked.noindex"
            release.archive_and_extract(self.app, archive, unpacked)
            self.assertTrue(archive.exists())
            extracted = unpacked / "日距.app"
            self.assertTrue(extracted.exists())
            result = subprocess.run(["/usr/bin/codesign", "--verify", "--deep", "--strict", "--all-architectures", str(extracted)], capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr.decode())
            self.assertEqual((extracted / "Contents/Info.plist").read_bytes(), (self.app / "Contents/Info.plist").read_bytes())

    def testNativeInspectionReadsBothDeploymentTargets(self):
        facts = release.inspect(self.app, TEAM, "notarization-input")
        self.assertTrue(facts["nested_valid"])
        for bundle in facts["bundles"]:
            self.assertEqual(set(bundle["architectures"]), {"arm64", "x86_64"})
            self.assertEqual(bundle["binary_minimum_os"], {"arm64": "14.0", "x86_64": "14.0"})
            self.assertFalse(bundle["developer_id"])

    def testOutputDirectoryAliasCannotWriteInsideSourceApp(self):
        with tempfile.TemporaryDirectory(suffix=".noindex") as directory:
            root = Path(directory)
            app = root / "Source.app"; app.mkdir()
            alias = root / "alias"; alias.symlink_to(app, target_is_directory=True)
            with self.assertRaisesRegex(ValueError, "separate"):
                release.package(app, alias / "candidate.zip", TEAM, GROUP, "notarization-input")
            self.assertEqual(list(app.iterdir()), [])

    def testOutputDirectoryCaseAliasCannotWriteInsideSourceApp(self):
        with tempfile.TemporaryDirectory(suffix=".noindex") as directory:
            root = Path(directory)
            app = root / "Source.app"; app.mkdir()
            alias = root / "SOURCE.APP"
            if not alias.exists(): self.skipTest("Case-sensitive filesystem")
            self.assertTrue(alias.samefile(app))
            with self.assertRaisesRegex(ValueError, "separate"):
                release.package(app, alias / "new-directory/candidate.zip", TEAM, GROUP, "notarization-input")
            self.assertEqual(list(app.iterdir()), [])

    def testBinaryDeploymentTargetMustMatchBothArchitectures(self):
        for minimum in [{"arm64": "26.0", "x86_64": "14.0"}, {"arm64": "14.0", "x86_64": "26.0"}, {"arm64": "14.0"}, {}]:
            facts = good_facts(); facts["bundles"][1]["binary_minimum_os"] = minimum
            self.assertTrue(release.evaluate(facts, TEAM, GROUP, "notarization-input")["errors"])

    def testPackageNeverReplacesExistingOutput(self):
        with tempfile.TemporaryDirectory(suffix=".noindex") as directory:
            output = Path(directory) / "candidate.zip"; output.write_bytes(b"keep")
            with self.assertRaises(FileExistsError):
                release.package(self.app, output, TEAM, GROUP, "notarization-input")
            self.assertEqual(output.read_bytes(), b"keep")

    def testSignedInputIsOnlyReadyForNotarization(self):
        result = release.evaluate(good_facts(), TEAM, GROUP, "notarization-input")
        self.assertEqual(result["status"], "ready_for_notarization")
        self.assertFalse(result["distributable"])
        self.assertEqual(result["errors"], [])

    def testDebugAdhocAndWrongTeamAreRejected(self):
        for field, value in [("developer_id", False), ("team", "Z9Y8X7W6V5"), ("storage", "local"), ("runtime", False), ("timestamp", False), ("verified", False)]:
            with self.subTest(field=field):
                facts = good_facts(); facts["bundles"][1][field] = value
                self.assertEqual(release.evaluate(facts, TEAM, GROUP, "notarization-input")["status"], "blocked")

    def testVersionIdentifierArchitectureAndMinimumMismatchAreRejected(self):
        for field, value in [("version", "1.2"), ("build", "6"), ("identifier", "other.app"), ("architectures", ["x86_64"]), ("minimum_os", "26.0"), ("group", "group.local.daydistance.shared")]:
            facts = good_facts(); facts["bundles"][1][field] = value
            self.assertTrue(release.evaluate(facts, TEAM, GROUP, "notarization-input")["errors"], field)

    def testEntitlementExceptionsAndWrongGroupAreRejected(self):
        for key, value in [("com.apple.security.get-task-allow", True), ("com.apple.security.cs.disable-library-validation", True),
                           ("com.apple.security.temporary-exception.files.home-relative-path.read-write", ["/Library/Application Support/"]),
                           ("com.apple.security.application-groups", ["group.local.daydistance.shared"]),
                           ("com.apple.security.app-sandbox", False)]:
            facts = good_facts(); facts["bundles"][0]["entitlements"][key] = value
            self.assertTrue(release.evaluate(facts, TEAM, GROUP, "notarization-input")["errors"], key)

    def testNestedFailureDebugFilesAndUnexpectedHelpersAreRejected(self):
        for field, value in [("nested_valid", False), ("debug_files", ["__preview.dylib"]), ("unexpected_code", ["helper.app"])]:
            facts = good_facts(); facts[field] = value
            self.assertTrue(release.evaluate(facts, TEAM, GROUP, "notarization-input")["errors"])

    def testOnlyMainAppCanAccessUserSelectedFiles(self):
        for index, key, value in [(0, "read-write", False), (1, "read-write", True), (1, "read-only", True)]:
            facts = good_facts(); facts["bundles"][index]["entitlements"]["com.apple.security.files.user-selected." + key] = value
            self.assertTrue(release.evaluate(facts, TEAM, GROUP, "notarization-input")["errors"])

    def testGroupAndTeamMustBeExplicitAndTeamPrefixed(self):
        for team, group in [("", GROUP), (TEAM, ""), (TEAM, "group.local.daydistance.shared"), (TEAM, "Z9Y8X7W6V5.shared")]:
            self.assertTrue(release.evaluate(good_facts(), team, group, "notarization-input")["errors"])

    def testDistributionRequiresBothStapleAndGatekeeper(self):
        facts = good_facts()
        self.assertFalse(release.evaluate(facts, TEAM, GROUP, "distribution")["distributable"])
        facts["stapled"] = True
        self.assertFalse(release.evaluate(facts, TEAM, GROUP, "distribution")["distributable"])
        facts["gatekeeper"] = True
        self.assertTrue(release.evaluate(facts, TEAM, GROUP, "distribution")["distributable"])

    def testRealAdhocBundleCannotCreatePackageOrAlterExistingOutput(self):
        # Real ad hoc signatures, without using an installed app or user files.
        with tempfile.TemporaryDirectory(suffix=".noindex") as directory:
            output = Path(directory) / "existing.zip"
            output.write_bytes(b"keep existing artifact")
            result = subprocess.run([sys.executable, str(Path(release.__file__)), str(self.app), "--team", TEAM,
                "--group", GROUP, "--package", str(output)], capture_output=True, text=True, timeout=30)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(output.read_bytes(), b"keep existing artifact")
            output.unlink()
            result = subprocess.run([sys.executable, str(Path(release.__file__)), str(self.app), "--team", TEAM,
                "--group", GROUP, "--package", str(output)], capture_output=True, text=True, timeout=30)
            self.assertNotEqual(result.returncode, 0)
            self.assertFalse(output.exists())
            report = json.loads(result.stdout)
            self.assertEqual(report["status"], "blocked")
            self.assertFalse(report["distributable"])
            self.assertIn("developer_id", " ".join(report["errors"]))


if __name__ == "__main__": unittest.main()
