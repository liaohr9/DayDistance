"""Exercise update safety on temporary bundles without touching LaunchServices."""
import importlib.util
import plistlib
import tempfile
import unittest
import subprocess
from unittest.mock import patch
from pathlib import Path

spec = importlib.util.spec_from_file_location("install_app", Path(__file__).with_name("install_app.py"))
installer = importlib.util.module_from_spec(spec)
spec.loader.exec_module(installer)


def bundle(path, marker, version="1.3", widget_version=None, identifier="local.daydistance.mac"):
    path.mkdir(parents=True)
    main = path / "Contents"
    main.mkdir()
    info = {"CFBundleIdentifier": identifier, "CFBundleShortVersionString": version,
            "CFBundleVersion": "4", "CFBundleExecutable": "DayDistance"}
    (main / "Info.plist").write_bytes(plistlib.dumps(info))
    (main / "marker").write_text(marker)
    widget = main / "PlugIns/DayDistanceWidget.appex/Contents"
    widget.mkdir(parents=True)
    info.update(CFBundleIdentifier="local.daydistance.mac.widget",
                CFBundleShortVersionString=widget_version or version)
    (widget / "Info.plist").write_bytes(plistlib.dumps(info))


class Runtime:
    """Only signing, process and system registration boundaries are replaced."""
    def __init__(self, running=False, reject_registration=False):
        self.running = running
        self.reject_registration = reject_registration
    def verify(self, app): pass
    def main_running(self): return self.running
    def stop_extension(self, app): pass
    def unregister(self, app): pass
    def register(self, app):
        if self.reject_registration and (app / "Contents/marker").read_text() == "new":
            raise RuntimeError("registration rejected")


class InstallSafetyTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(suffix=".noindex")
        self.root = Path(self.temp.name)
        self.source = self.root / "candidate.app"
        self.destination = self.root / "Applications/日距.app"
        self.destination.parent.mkdir()
        self.backups = self.root / "backups"
        bundle(self.source, "new")
        bundle(self.destination, "old", version="1.2")
    def tearDown(self): self.temp.cleanup()
    def install(self, runtime=None):
        return installer.install(self.source, self.destination, self.backups, runtime or Runtime())
    def test_update_keeps_one_installed_app_and_recoverable_zip(self):
        self.install()
        self.assertEqual((self.destination / "Contents/marker").read_text(), "new")
        self.assertEqual((self.source / "Contents/marker").read_text(), "new")
        self.assertEqual(len(list(self.backups.glob("*.zip"))), 1)
        self.assertEqual(list(self.destination.parent.glob("*.app")), [self.destination])
    def test_running_app_refuses_update_without_overwriting(self):
        with self.assertRaisesRegex(RuntimeError, "running"):
            self.install(Runtime(running=True))
        self.assertEqual((self.destination / "Contents/marker").read_text(), "old")
        self.assertFalse(self.backups.exists())
    def test_widget_version_mismatch_does_not_replace_installed_app(self):
        info = self.source / "Contents/PlugIns/DayDistanceWidget.appex/Contents/Info.plist"
        value = plistlib.loads(info.read_bytes())
        value["CFBundleShortVersionString"] = "1.0"
        info.write_bytes(plistlib.dumps(value))
        with self.assertRaisesRegex(ValueError, "version"):
            self.install()
        self.assertEqual((self.destination / "Contents/marker").read_text(), "old")
    def test_registration_failure_restores_previous_bundle(self):
        with self.assertRaisesRegex(RuntimeError, "registration rejected"):
            self.install(Runtime(reject_registration=True))
        self.assertEqual((self.destination / "Contents/marker").read_text(), "old")
        self.assertEqual(list(self.destination.parent.glob("*.app")), [self.destination])
    def test_unrelated_destination_is_never_overwritten(self):
        info = self.destination / "Contents/Info.plist"
        value = plistlib.loads(info.read_bytes())
        value["CFBundleIdentifier"] = "com.example.other"
        info.write_bytes(plistlib.dumps(value))
        with self.assertRaisesRegex(ValueError, "identifier"):
            self.install()
        self.assertEqual((self.destination / "Contents/marker").read_text(), "old")
    def test_failed_rollback_preserves_previous_bundle_for_manual_recovery(self):
        rename = installer.os.replace
        def fail_restore(source, destination):
            if Path(source).name == "previous.app": raise OSError("restore blocked")
            return rename(source, destination)
        with patch.object(installer.os, "replace", side_effect=fail_restore):
            with self.assertRaisesRegex(OSError, "restore blocked"):
                self.install(Runtime(reject_registration=True))
        previous = list(self.destination.parent.glob(".daydistance-install-*.noindex/previous.app/Contents/marker"))
        self.assertEqual(len(previous), 1)
        self.assertEqual(previous[0].read_text(), "old")
    def test_app_opened_during_staging_defers_update_without_overwriting(self):
        class OpensDuringCopy(Runtime):
            def __init__(self): self.checks = 0
            def main_running(self):
                self.checks += 1
                return self.checks >= 2
        with self.assertRaisesRegex(RuntimeError, "running"):
            self.install(OpensDuringCopy())
        self.assertEqual((self.destination / "Contents/marker").read_text(), "old")
        self.assertFalse(self.backups.exists())
    def test_process_query_failure_does_not_allow_install(self):
        runtime = installer.MacRuntime()
        with patch.object(installer.subprocess, "run", return_value=subprocess.CompletedProcess([], 2)):
            with self.assertRaisesRegex(RuntimeError, "process"):
                runtime.main_running()
    def test_old_registration_removed_before_replacement(self):
        removed = []
        class UpdateRuntime(Runtime):
            def unregister(inner, app):
                removed.append((app, (app / "Contents/marker").read_text()))
        self.install(UpdateRuntime())
        self.assertEqual(removed, [(self.destination, "old")])
    def test_unregister_failure_preserves_old_app(self):
        class BlockedRuntime(Runtime):
            def unregister(inner, app): raise RuntimeError("unregister blocked")
        with self.assertRaisesRegex(RuntimeError, "unregister blocked"):
            self.install(BlockedRuntime())
        self.assertEqual((self.destination / "Contents/marker").read_text(), "old")
    def test_unregister_targets_only_old_bundle(self):
        with patch.object(installer.subprocess, "run", return_value=subprocess.CompletedProcess([], 0)) as command:
            installer.MacRuntime().unregister(self.destination)
        self.assertEqual(command.call_args.args[0], [installer.REGISTER, "-u", str(self.destination)])
    def test_mixed_signing_modes_are_rejected(self):
        values = [subprocess.CompletedProcess([], 0),
                  subprocess.CompletedProcess([], 0, stdout="", stderr="Signature=adhoc\nTeamIdentifier=not set\n"),
                  subprocess.CompletedProcess([], 0, stdout="", stderr="Authority=Apple Development\nTeamIdentifier=TEAM123\n")]
        with patch.object(installer.subprocess, "run", side_effect=values):
            with self.assertRaisesRegex(ValueError, "signing"):
                installer.MacRuntime().verify(self.source)
    def test_different_signing_teams_are_rejected(self):
        values = [subprocess.CompletedProcess([], 0),
                  subprocess.CompletedProcess([], 0, stdout="", stderr="Authority=Apple Development\nTeamIdentifier=TEAM123\n"),
                  subprocess.CompletedProcess([], 0, stdout="", stderr="Authority=Apple Development\nTeamIdentifier=TEAM456\n")]
        with patch.object(installer.subprocess, "run", side_effect=values):
            with self.assertRaisesRegex(ValueError, "signing"):
                installer.MacRuntime().verify(self.source)
    def test_cleanup_failures_still_restore_installed_registration(self):
        for failing_step in ("stop", "pluginkit", "lsregister"):
            with self.subTest(failing_step=failing_step):
                restored = []
                class CleanupRuntime(Runtime):
                    def stop_extension(inner, app):
                        if failing_step == "stop": raise RuntimeError("stop blocked")
                    def register(inner, app): restored.append(app)
                def command(args, **kwargs):
                    failed = ((failing_step == "pluginkit" and args[0] == "/usr/bin/pluginkit") or
                              (failing_step == "lsregister" and args[0] == installer.REGISTER))
                    return subprocess.CompletedProcess(args, int(failed), stdout="", stderr="cleanup blocked" if failed else "")
                with patch.object(installer.subprocess, "run", side_effect=command):
                    with self.assertRaisesRegex(RuntimeError, "blocked"):
                        installer.cleanup_registration(self.source, self.destination, CleanupRuntime())
                self.assertEqual(restored, [self.destination])
                self.assertEqual((self.destination / "Contents/marker").read_text(), "old")


if __name__ == "__main__": unittest.main()
