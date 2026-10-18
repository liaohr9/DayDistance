#!/usr/bin/env python3
"""Package an explicitly unnotarized developer preview; never changes signing or installs."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import zipfile


def run(*arguments):
    return subprocess.run(arguments, check=True, capture_output=True)


def verify(app):
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    assert info['CFBundleIdentifier'] == 'local.daydistance.mac'
    assert info['DayDistanceStorageMode'] == 'local', 'Use prepare_release.py for formal shared builds'
    widget = app / 'Contents/PlugIns/DayDistanceWidget.appex'
    for bundle in [app, widget]:
        details = plistlib.loads((bundle / 'Contents/Info.plist').read_bytes())
        assert details['CFBundleShortVersionString'] == info['CFBundleShortVersionString']
        assert details['CFBundleVersion'] == info['CFBundleVersion']
        binary = bundle / 'Contents/MacOS' / details['CFBundleExecutable']
        assert set(run('/usr/bin/lipo', '-archs', str(binary)).stdout.decode().split()) == {'arm64'}
        entitlements = plistlib.loads(run('/usr/bin/codesign', '-d', '--entitlements', ':-', str(bundle)).stdout)
        assert entitlements.get('com.apple.security.app-sandbox') is True
        assert not entitlements.get('com.apple.security.get-task-allow')
    run('/usr/bin/codesign', '--verify', '--deep', '--strict', '--all-architectures', str(app))
    assert not list(app.rglob('*.debug.dylib'))
    assert not list(app.rglob('events.json')), 'No user data may be packaged'
    return info


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('app', type=Path)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    info = verify(args.app)
    output = args.output.resolve(); output.mkdir(parents=True, exist_ok=True)
    stem = f"DayDistance-{info['CFBundleShortVersionString']}-macOS-arm64-preview"
    archive = output / (stem + '.zip'); image = output / (stem + '.dmg')
    sums = output / 'SHA256SUMS.txt'; manifest = output / 'BUILD_INFO.json'
    if any(f.exists() for f in [archive, image, sums, manifest]):
        raise FileExistsError('Refusing to overwrite an existing preview artifact')
    with tempfile.TemporaryDirectory(prefix='daydistance-preview-', suffix='.noindex') as folder:
        root = Path(folder); stage = root / 'image'; stage.mkdir()
        app = stage / '日距.app'; shutil.copytree(args.app, app, symlinks=True)
        verify(app)
        run('/usr/bin/ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', str(app), str(archive))
        with zipfile.ZipFile(archive) as zipped:
            assert zipped.testzip() is None
        unpacked = root / 'unpacked.noindex'
        run('/usr/bin/ditto', '-x', '-k', str(archive), str(unpacked))
        verify(unpacked / '日距.app')
        (stage / 'Applications').symlink_to('/Applications', target_is_directory=True)
        (stage / '请先阅读 - Developer Preview.txt').write_text(
            '日距 / DayDistance — 开发预览\n\n'
            '此包使用本地 ad hoc 签名，未完成 Developer ID 签名与 Apple 公证。\n'
            '互联网下载后 macOS 可能阻止打开。DMG 不会消除该限制。\n'
            '若系统阻止运行，请等待公证版或从源码构建；不要关闭系统安全保护。\n'
            '升级前导出事件备份，保存或取消编辑并退出旧版，只保留一份应用。\n\n'
            'This is an unnotarized, ad hoc-signed developer preview.\n'
            'macOS may block downloaded builds. Wait for notarization or build from source.\n'
            'https://github.com/liaohr9/DayDistance\n')
        run('/usr/bin/hdiutil', 'create', '-volname', '日距 ' + info['CFBundleShortVersionString'] + ' 预览',
            '-srcfolder', str(stage), '-format', 'UDZO', str(image))
        run('/usr/bin/hdiutil', 'verify', str(image))
    records = [{'name': f.name, 'bytes': f.stat().st_size, 'sha256': hashlib.sha256(f.read_bytes()).hexdigest()} for f in [image, archive]]
    sums.write_text(''.join(f"{r['sha256']}  {r['name']}\n" for r in records))
    manifest.write_text(json.dumps({'version': info['CFBundleShortVersionString'], 'build': info['CFBundleVersion'],
        'channel': 'unnotarized-developer-preview', 'architectures': ['arm64'],
        'storage': 'local', 'developerID': False, 'notarized': False,
        'signatureVerification': 'strict nested signature and ZIP roundtrip passed', 'artifacts': records}, indent=2) + '\n')
    print(json.dumps(records, indent=2))


if __name__ == '__main__':
    main()
