#!/usr/bin/env python3
"""Compile the real updater with disposable preferences and injected HTTP responses."""
import os, platform, subprocess, tempfile
from pathlib import Path
p = Path(__file__).resolve().parent.parent
env = dict(os.environ)
with tempfile.TemporaryDirectory(suffix='.noindex') as root:
    binary = str(Path(root)/'updates-probe')
    sources = list((p/'Shared/Core').glob('*.swift')) + [p/'App/Services/UpdateController.swift', p/'Tests/Fixtures/UpdatesProbe.swift']
    subprocess.run(['xcrun','swiftc','-parse-as-library','-target',f'{platform.machine()}-apple-macos14.0',*map(str,sources),'-o',binary],env=env,check=True,timeout=120)
    subprocess.run([binary],check=True,timeout=30)
