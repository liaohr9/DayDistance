#!/usr/bin/env python3
"""Verify fault controls refuse escaped paths and preserve disposable JSON bytes."""
import contextlib
import io
import json
import os
from pathlib import Path
import plistlib
import sys
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from control_ui_probe import main, temporary_probe
from run_ui_probe import restore_data_permissions


class FaultControlTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.build = tempfile.TemporaryDirectory(suffix=".noindex")
        cls.addClassCleanup(cls.build.cleanup)
        cls.writer = str(Path(cls.build.name) / "writer")
        project = Path(__file__).resolve().parent.parent
        env = os.environ.copy()
        env.setdefault("DEVELOPER_DIR", "/Volumes/haoran 1/Applications/Xcode.app/Contents/Developer")
        subprocess.run(["/usr/bin/xcrun", "swiftc", "-parse-as-library", str(project / "Shared/Core/L10n.swift"), str(project / "Shared/Core/Event.swift"), str(project / "Shared/Core/EventDates.swift"),
                        str(project / "Shared/Core/EventRepository.swift"), str(project / "Shared/Core/ExportDestinationPolicy.swift"), str(project / "Tests/Fixtures/UIWriterProbe.swift"),
                        "-o", cls.writer], env=env, check=True, timeout=90)

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="daydistance-ui-", suffix=".noindex")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        self.data = self.root / "data"
        self.data.mkdir()
        self.addCleanup(lambda: self.data.chmod(0o700) if self.data.exists() and not self.data.is_symlink() else None)
        app = self.root / "日距列表验证.app/Contents"
        app.mkdir(parents=True)
        self.info = app / "Info.plist"
        self.info.write_bytes(plistlib.dumps({"CFBundleIdentifier": "local.daydistance.uiprobe"}))
        self.source = self.data / "events.json"
        self.source.write_text(json.dumps({"schemaVersion": 1, "events": [{"id": "8BFC9414-0410-4DDE-9F93-501383174EF4", "title": "仅临时测试",
            "targetDate": 812940000, "createdAt": 812940000, "updatedAt": 812940000, "symbol": "calendar", "colorKey": "sage"}]}))
        (self.data / "events.json.lock").touch()
        (self.root / "writer").touch()

    def control(self, operation):
        output = io.StringIO()
        with patch.object(sys, "argv", ["control_ui_probe.py", operation, str(self.root)]), contextlib.redirect_stdout(output):
            main()
        return json.loads(output.getvalue())

    def test_inspect_corrupt_bytes_without_modification(self):
        raw = b'{"schemaVersion":'
        self.source.write_bytes(raw)
        result = self.control("inspect")
        self.assertFalse(result["valid_json"])
        self.assertEqual(self.source.read_bytes(), raw)

    def test_recover_preserves_exact_baseline_and_lock(self):
        baseline = self.source.read_bytes()
        (self.root / "baseline.json").write_bytes(baseline)
        self.source.write_bytes(b'{"schemaVersion":')
        lock = self.data / "events.json.lock"
        inode = lock.stat().st_ino
        self.control("recover")
        self.assertEqual(self.source.read_bytes(), baseline)
        self.assertEqual(lock.stat().st_ino, inode)

    def test_recover_refuses_symlink_baseline(self):
        with tempfile.TemporaryDirectory() as other:
            outside = Path(other) / "outside.json"
            outside.write_bytes(self.source.read_bytes())
            (self.root / "baseline.json").symlink_to(outside)
            original = self.source.read_bytes()
            with self.assertRaises(ValueError):
                self.control("recover")
            self.assertEqual(self.source.read_bytes(), original)
            self.assertEqual(outside.read_bytes(), original)

    def test_recover_refuses_invalid_baseline(self):
        original = self.source.read_bytes()
        for raw in (b"broken", b'{"schemaVersion":8,"events":[]}', b'{"schemaVersion":1}'):
            with self.subTest(raw=raw):
                (self.root / "baseline.json").write_bytes(raw)
                with self.assertRaises(ValueError):
                    self.control("recover")
                self.assertEqual(self.source.read_bytes(), original)

    def test_recover_refuses_busy_lock(self):
        import fcntl
        original = self.source.read_bytes()
        (self.root / "baseline.json").write_bytes(original)
        with (self.data / "events.json.lock").open("r+") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            with self.assertRaises(BlockingIOError):
                self.control("recover")
        self.assertEqual(self.source.read_bytes(), original)

    def test_running_fault_preserves_baseline_and_lock(self):
        original = self.source.read_bytes()
        baseline = self.root / "baseline.json"
        baseline.write_bytes(original)
        inode = (self.data / "events.json.lock").stat().st_ino
        for operation in ("corrupt", "newer"):
            with self.subTest(operation=operation):
                result = self.control(operation)
                if operation == "corrupt":
                    self.assertFalse(result["valid_json"])
                else:
                    self.assertEqual(result["schema_version"], 8)
                self.assertEqual(baseline.read_bytes(), original)
                self.assertEqual((self.data / "events.json.lock").stat().st_ino, inode)
                self.control("recover")
                self.assertEqual(self.source.read_bytes(), original)

    def test_running_fault_refuses_busy_lock(self):
        import fcntl
        original = self.source.read_bytes()
        (self.root / "baseline.json").write_bytes(original)
        with (self.data / "events.json.lock").open("r+") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            for operation in ("corrupt", "newer"):
                with self.subTest(operation=operation), self.assertRaises(BlockingIOError):
                    self.control(operation)
        self.assertEqual(self.source.read_bytes(), original)

    def test_valid_disposable_fixture(self):
        self.assertEqual(temporary_probe(str(self.root)), self.root)

    def test_valid_writer_updates_only_fixture(self):
        result = subprocess.run([self.writer, str(self.root)], capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr.decode())
        self.assertEqual(json.loads(self.source.read_bytes())["events"][0]["title"], "其他进程保存的名称")

    def test_reject_unrelated_temp_folder(self):
        with tempfile.TemporaryDirectory() as other:
            with self.assertRaises(ValueError):
                temporary_probe(other)

    def test_reject_nested_folder(self):
        child = self.root / "daydistance-ui-child.noindex"
        child.mkdir()
        with self.assertRaises(ValueError):
            temporary_probe(str(child))

    def test_reject_product_identity(self):
        self.info.write_bytes(plistlib.dumps({"CFBundleIdentifier": "local.daydistance.mac"}))
        with self.assertRaises(ValueError):
            temporary_probe(str(self.root))

    def test_reject_symlink_escape(self):
        with tempfile.TemporaryDirectory() as other:
            outside = Path(other) / "outside"
            outside.write_bytes(b"must remain unchanged")
            for target in (self.source, self.data / "events.json.lock", self.root / "writer"):
                with self.subTest(target=target.name):
                    original = target.read_bytes()
                    target.unlink()
                    target.symlink_to(outside)
                    with self.assertRaises(ValueError):
                        temporary_probe(str(self.root))
                    self.assertEqual(outside.read_bytes(), b"must remain unchanged")
                    target.unlink()
                    target.write_bytes(original)
            other_data = Path(other) / "data"
            other_data.mkdir()
            saved_data = self.root / "saved-data"
            self.data.rename(saved_data)
            self.data.symlink_to(other_data, target_is_directory=True)
            with self.assertRaises(ValueError):
                temporary_probe(str(self.root))
            self.data.unlink()
            saved_data.rename(self.data)

    def test_permission_controls_preserve_data(self):
        original = self.source.read_bytes()
        for operation, mode in (("read-only", 0o500), ("writable", 0o700)):
            output = io.StringIO()
            with patch.object(sys, "argv", ["control_ui_probe.py", operation, str(self.root)]), contextlib.redirect_stdout(output):
                main()
            self.assertEqual(self.data.stat().st_mode & 0o777, mode)
            self.assertEqual(self.source.read_bytes(), original)
            self.assertEqual(json.loads(output.getvalue())["events"][0]["title"], "仅临时测试")

    def test_writer_independently_rejects_symlink_escape(self):
        original = self.source.read_bytes()
        with tempfile.TemporaryDirectory() as other:
            outside = Path(other)
            outside_source = outside / "events.json"
            outside_lock = outside / "events.json.lock"
            outside_source.write_bytes(original)
            outside_lock.touch()
            saved = self.root / "saved-data"
            self.data.rename(saved)
            self.data.symlink_to(outside, target_is_directory=True)
            result = subprocess.run([self.writer, str(self.root)], capture_output=True)
            self.data.unlink()
            saved.rename(self.data)
            self.assertNotEqual(result.returncode, 0)
            self.assertEqual(outside_source.read_bytes(), original)
            for source, target in ((self.source, outside_source), (self.data / "events.json.lock", outside_lock)):
                with self.subTest(path=source.name):
                    before = source.read_bytes()
                    source.unlink()
                    source.symlink_to(target)
                    result = subprocess.run([self.writer, str(self.root)], capture_output=True)
                    source.unlink()
                    source.write_bytes(before)
                    self.assertNotEqual(result.returncode, 0)
                    self.assertEqual(outside_source.read_bytes(), original)

    def test_cleanup_does_not_chmod_symlink_destination(self):
        with tempfile.TemporaryDirectory() as other:
            outside = Path(other)
            outside.chmod(0o500)
            saved = self.root / "saved-data"
            self.data.rename(saved)
            self.data.symlink_to(outside, target_is_directory=True)
            restore_data_permissions(self.root)
            self.data.unlink()
            saved.rename(self.data)
            self.assertEqual(outside.stat().st_mode & 0o777, 0o500)


if __name__ == "__main__":
    unittest.main()
