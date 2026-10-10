"""Bounded disk-image fixture for disposable UI tests only."""
from contextlib import contextmanager
import errno
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import tempfile

MAX_VOLUME_BYTES = 64 * 1024 * 1024
MAX_IMAGE_BYTES = MAX_VOLUME_BYTES + 1024 * 1024


def live_image_info():
    return plistlib.loads(subprocess.check_output(["/usr/bin/hdiutil", "info", "-plist"], timeout=15))


def device_id(path):
    return Path(path).stat().st_dev


def capacity_bytes(path):
    stat = os.statvfs(path)
    return stat.f_blocks * stat.f_frsize


def probe_root(value):
    given = Path(value)
    if given.is_symlink():
        raise ValueError("QA root must not be a symlink")
    root = given.resolve(strict=True)
    if root.parent != Path(tempfile.gettempdir()).resolve() or not root.name.startswith("daydistance-ui-") or root.suffix != ".noindex":
        raise ValueError("Expected a direct system temporary QA folder")
    return root


def validate_disk(value):
    root = probe_root(value)
    image = root / "qa-disk.dmg"
    data = root / "data"
    if image.is_symlink() or data.is_symlink() or not image.is_file() or not data.is_dir():
        raise ValueError("Expected regular owned image and mount point")
    if image.stat().st_size > MAX_IMAGE_BYTES:
        raise ValueError("QA image exceeds its size limit")
    if not os.path.ismount(data) or device_id(data) == device_id(root):
        raise ValueError("Refusing host storage or an unmounted directory")
    if not 0 < capacity_bytes(data) <= MAX_VOLUME_BYTES:
        raise ValueError("QA volume exceeds its capacity limit")
    matched = any(
        item.get("image-path") == str(image) and any(
            entity.get("mount-point") == str(data)
            for entity in item.get("system-entities", [])
        ) for item in live_image_info().get("images", [])
    )
    if not matched:
        raise ValueError("Live mounted image does not match the owned QA image")
    return data


def fill_disk(root):
    data = validate_disk(root)
    filler = data / "disk-full-filler.bin"
    if filler.is_symlink() or filler.exists():
        raise ValueError("Refusing an existing filler path")
    # Exclusive creation and a hard byte budget bound even a malformed fixture.
    descriptor = os.open(filler, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    written = 0
    chunk_size = 1024 * 1024
    block = os.urandom(chunk_size)
    saw_full = False
    try:
        while written < MAX_VOLUME_BYTES:
            try:
                amount = os.write(descriptor, block[:min(chunk_size, MAX_VOLUME_BYTES - written)])
                if amount <= 0:
                    raise RuntimeError("Filler made no progress")
                written += amount
            except OSError as error:
                if error.errno != errno.ENOSPC:
                    raise
                saw_full = True
                if chunk_size == 512:
                    break
                chunk_size = max(512, chunk_size // 16)
        try:
            os.fsync(descriptor)
        except OSError as error:
            if error.errno != errno.ENOSPC:
                raise
            saw_full = True
    finally:
        os.close(descriptor)
    if not saw_full:
        raise RuntimeError("Reached QA byte limit without ENOSPC; no further writes allowed")
    stat = os.statvfs(data)
    return {"filler_bytes": written, "write_errno": errno.ENOSPC,
            "available_bytes": stat.f_bavail * stat.f_frsize}


def release_space(root):
    data = validate_disk(root)
    filler = data / "disk-full-filler.bin"
    if filler.is_symlink() or not filler.is_file() or filler.stat().st_size > MAX_VOLUME_BYTES:
        raise ValueError("Expected the bounded regular QA filler")
    filler.unlink()


def cleanup_probe_folder(value):
    root = probe_root(value)
    data = root / "data"
    image = root / "qa-disk.dmg"
    if image.is_symlink() or data.is_symlink():
        raise ValueError("Refusing aliased cleanup paths")
    # Attach can create a device before mounting (or before a timeout). Check
    # the live image association even when data is not a mount point.
    owned = [item for item in live_image_info().get("images", []) if item.get("image-path") == str(image)]
    if len(owned) > 1:
        raise ValueError("Unexpected duplicate QA image attachments; retaining folder")
    if os.path.ismount(data):
        validate_disk(root)
    if owned:
        devices = [entity.get("dev-entry", "") for entity in owned[0].get("system-entities", [])]
        whole = next((device for device in devices if re.fullmatch(r"/dev/disk[0-9]+", device)), None)
        if whole is None:
            raise ValueError("No whole device associated with the QA image; retaining folder")
        subprocess.run(["/usr/bin/hdiutil", "detach", whole], check=True, timeout=30,
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if any(item.get("image-path") == str(image) for item in live_image_info().get("images", [])):
            raise RuntimeError("QA image remains attached; retaining its folder")
    if os.path.ismount(data):
        raise RuntimeError("QA volume remains mounted; retaining its folder")
    # Only a freshly created direct temporary QA root can reach this cleanup.
    shutil.rmtree(root)


@contextmanager
def probe_folder(disk=False):
    root = Path(tempfile.mkdtemp(prefix="daydistance-ui-", suffix=".noindex")).resolve()
    try:
        if disk:
            data = root / "data"
            data.mkdir()
            image = root / "qa-disk.dmg"
            subprocess.run(["/usr/bin/hdiutil", "create", "-size", "64m", "-fs", "APFS", "-type", "UDIF",
                            "-volname", "DayDistanceQA.noindex", str(image)], check=True, timeout=45,
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            subprocess.run(["/usr/bin/hdiutil", "attach", "-nobrowse", "-noautoopen", "-mountpoint", str(data),
                            str(image)], check=True, timeout=45, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            validate_disk(root)
        yield str(root)
    finally:
        try:
            cleanup_probe_folder(root)
        except Exception:
            # Never recurse into a mounted volume when detach fails.
            print(f"QA cleanup incomplete; retained folder: {root}", flush=True)
            raise
