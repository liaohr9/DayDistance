#!/usr/bin/env python3
"""Exercise production settings routing and data guards on disposable state."""
import os, platform, subprocess, tempfile
from pathlib import Path
p = Path(__file__).resolve().parent.parent
env = dict(os.environ)
sources = list((p/'Shared/Core').glob('*.swift')) + list((p/'Shared/Presentation').glob('*.swift')) + [p/'Shared/Platform/SharedContainer.swift'] + list((p/'App/Stores').glob('*.swift')) + list((p/'App/Views').glob('*.swift')) + list((p/'App/Services').glob('*.swift')) + [p/'Tests/Fixtures/SettingsProbe.swift']
with tempfile.TemporaryDirectory(suffix='.noindex') as root:
    binary = str(Path(root)/'settings-probe')
    subprocess.run(['xcrun','swiftc','-parse-as-library','-target',f'{platform.machine()}-apple-macos14.0',*map(str,sources),'-o',binary],env=env,check=True,timeout=120)
    subprocess.run([binary,root],check=True,timeout=15)
