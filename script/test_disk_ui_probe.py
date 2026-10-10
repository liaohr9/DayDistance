#!/usr/bin/env python3
"""Check disposable-volume controls cannot fill host storage or escaped paths."""
import contextlib
import errno
from pathlib import Path
import tempfile
import subprocess
import unittest
from unittest.mock import patch

from disk_ui_probe import validate_disk, fill_disk, release_space, cleanup_probe_folder


class DiskControlsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="daydistance-ui-", suffix=".noindex")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.data = self.root / "data"
        self.data.mkdir()
        self.image = self.root / "qa-disk.dmg"
        self.image.touch()
        self.source = self.data / "events.json"
        self.source.write_bytes(b"preserve this fixture")
        self.info = {"images": [{"image-path": str(self.image), "system-entities": [
            {"dev-entry": "/dev/disk99"}, {"mount-point": str(self.data), "dev-entry": "/dev/disk99s1"}]}]}

    @contextlib.contextmanager
    def mounted(self, device=2, capacity=64*1024*1024):
        with patch("disk_ui_probe.live_image_info", return_value=self.info), \
             patch("disk_ui_probe.device_id", side_effect=lambda p: device if Path(p) == self.data else 1), \
             patch("disk_ui_probe.capacity_bytes", return_value=capacity), \
             patch("disk_ui_probe.os.path.ismount", return_value=True):
            yield

    def test_failed_detach_preserves_folder_and_bytes(self):
        with self.mounted(), patch("disk_ui_probe.subprocess.run", side_effect=subprocess.CalledProcessError(1, "hdiutil")):
            with self.assertRaises(subprocess.CalledProcessError):
                cleanup_probe_folder(self.root)
        self.assertTrue(self.root.exists())
        self.assertEqual(self.source.read_bytes(), b"preserve this fixture")

    def test_reject_non_qa_root(self):
        with self.assertRaises(ValueError):
            validate_disk(self.root.parent)

    def test_existing_regular_filler_is_not_overwritten(self):
        filler = self.data / "disk-full-filler.bin"
        filler.write_bytes(b"keep existing")
        with self.mounted(), self.assertRaises(ValueError):
            fill_disk(self.root)
        self.assertEqual(filler.read_bytes(), b"keep existing")

    def test_partial_attach_detaches_before_removing_folder(self):
        self.info["images"][0]["system-entities"] = [{"dev-entry": "/dev/disk99"}]
        with patch("disk_ui_probe.live_image_info", side_effect=[self.info, {"images": []}]),              patch("disk_ui_probe.os.path.ismount", return_value=False),              patch("disk_ui_probe.subprocess.run") as command:
            cleanup_probe_folder(self.root)
        self.assertFalse(self.root.exists())
        self.assertEqual(command.call_args.args[0], ["/usr/bin/hdiutil", "detach", "/dev/disk99"])

    def test_partial_attach_failure_preserves_image_and_folder(self):
        self.info["images"][0]["system-entities"] = [{"dev-entry": "/dev/disk99"}]
        with patch("disk_ui_probe.live_image_info", return_value=self.info),              patch("disk_ui_probe.os.path.ismount", return_value=False),              patch("disk_ui_probe.subprocess.run", side_effect=subprocess.CalledProcessError(1, "hdiutil")):
            with self.assertRaises(subprocess.CalledProcessError):
                cleanup_probe_folder(self.root)
        self.assertTrue(self.image.exists())
        self.assertEqual(self.source.read_bytes(), b"preserve this fixture")

    def test_cleanup_query_failure_preserves_folder(self):
        with patch("disk_ui_probe.live_image_info", side_effect=subprocess.CalledProcessError(1, "hdiutil")),              patch("disk_ui_probe.os.path.ismount", return_value=False):
            with self.assertRaises(subprocess.CalledProcessError):
                cleanup_probe_folder(self.root)
        self.assertTrue(self.image.exists())

    def test_accept_owned_bounded_volume(self):
        with self.mounted():
            self.assertEqual(validate_disk(self.root), self.data)

    def test_refuse_host_device_before_filling(self):
        original = self.source.read_bytes()
        with self.mounted(device=1), self.assertRaises(ValueError):
            fill_disk(self.root)
        self.assertEqual(self.source.read_bytes(), original)
        self.assertFalse((self.data / "disk-full-filler.bin").exists())

    def test_refuse_oversize_volume(self):
        with self.mounted(capacity=1024*1024*1024), self.assertRaises(ValueError):
            fill_disk(self.root)

    def test_refuse_unmatched_live_image(self):
        self.info["images"][0]["image-path"] = "/unrelated/image.dmg"
        with self.mounted(), self.assertRaises(ValueError):
            fill_disk(self.root)

    def test_refuse_image_and_data_symlink(self):
        with tempfile.TemporaryDirectory() as outside:
            target = Path(outside)
            self.image.unlink()
            self.image.symlink_to(target / "outside.dmg")
            with self.mounted(), self.assertRaises(ValueError):
                validate_disk(self.root)
            self.image.unlink(); self.image.touch()
            self.source.unlink(); self.data.rmdir()
            self.data.symlink_to(target, target_is_directory=True)
            with self.mounted(), self.assertRaises(ValueError):
                validate_disk(self.root)
            self.data.unlink(); self.data.mkdir()

    def test_refuse_unmounted_directory(self):
        with self.mounted(), patch("disk_ui_probe.os.path.ismount", return_value=False), self.assertRaises(ValueError):
            fill_disk(self.root)

    def test_filler_symlink_never_touches_external_bytes(self):
        with tempfile.TemporaryDirectory() as outside:
            target = Path(outside) / "original.bin"
            target.write_bytes(b"keep")
            (self.data / "disk-full-filler.bin").symlink_to(target)
            with self.mounted():
                for action in (fill_disk, release_space):
                    with self.subTest(action=action.__name__), self.assertRaises(ValueError):
                        action(self.root)
            self.assertEqual(target.read_bytes(), b"keep")

    def test_release_removes_only_filler(self):
        filler = self.data / "disk-full-filler.bin"
        filler.write_bytes(b"owned disposable filler")
        with self.mounted():
            release_space(self.root)
        self.assertFalse(filler.exists())
        self.assertEqual(self.source.read_bytes(), b"preserve this fixture")


if __name__ == "__main__":
    unittest.main()
