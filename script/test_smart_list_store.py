#!/usr/bin/env python3
"""Exercise production settings routing and data guards on disposable state."""
import os, platform, subprocess, tempfile, shutil
from pathlib import Path
p = Path(__file__).resolve().parent.parent
env = dict(os.environ)
env.setdefault('DEVELOPER_DIR', '/Volumes/haoran 1/Applications/Xcode.app/Contents/Developer')
sources = list((p/'Shared/Core').glob('*.swift')) + list((p/'Shared/Presentation').glob('*.swift')) + [p/'Shared/Platform/SharedContainer.swift'] + list((p/'App/Stores').glob('*.swift')) + list((p/'App/Views').glob('*.swift')) + list((p/'App/Services').glob('*.swift')) + [p/'Tests/Fixtures/SmartListStoreProbe.swift']
with tempfile.TemporaryDirectory(suffix='.noindex') as root:
    frozen = Path(root)/'sources'
    frozen.mkdir()
    snapshots = []
    for index, source in enumerate(sources):
        target = frozen / f'{index}-{source.name}'
        shutil.copyfile(source, target)
        snapshots.append(target)
    binary = str(Path(root)/'smart-list-store-probe')
    subprocess.run(['xcrun','swiftc','-parse-as-library','-target',f'{platform.machine()}-apple-macos14.0',*map(str,snapshots),'-o',binary],env=env,check=True,timeout=120)
    subprocess.run([binary,root],check=True,timeout=15)
