#!/usr/bin/env python3
"""Compile production automation services against disposable event data."""
import os,platform,subprocess,tempfile
from pathlib import Path
p=Path(__file__).resolve().parent.parent
sources=list((p/'Shared/Core').glob('*.swift'))+[p/'Shared/Platform/SharedContainer.swift',p/'App/Stores/EventStore.swift',p/'App/Services/EventHistoryUndoManager.swift',p/'App/Services/AutomationService.swift',p/'Tests/Fixtures/AutomationServiceProbe.swift']
with tempfile.TemporaryDirectory(suffix='.noindex') as folder:
    binary=Path(folder)/'probe'
    subprocess.run(['xcrun','swiftc','-parse-as-library','-target',f'{platform.machine()}-apple-macos14.0',*map(str,sources),'-o',str(binary)],env=os.environ,check=True,timeout=120)
    subprocess.run([str(binary),folder],check=True,timeout=20)
    with tempfile.TemporaryDirectory(suffix=".noindex") as zone_folder:
        for mode,zone in [("create","Asia/Shanghai"),("replay","America/Los_Angeles")]:
            subprocess.run([str(binary),zone_folder,mode],env=dict(os.environ,TZ=zone),check=True,timeout=20)

with tempfile.TemporaryDirectory(suffix='.noindex') as folder:
    binary=Path(folder)/'channel'
    subprocess.run(['xcrun','swiftc','-parse-as-library',*map(str,[p/'Shared/Core/AutomationProtocol.swift',p/'Shared/Core/EventDates.swift',p/'Shared/Core/Event.swift',p/'Shared/Core/L10n.swift',p/'App/Services/AutomationChannel.swift',p/'Tests/Fixtures/AutomationChannelProbe.swift']),'-o',str(binary)],check=True,timeout=120)
    subprocess.run([str(binary),folder],check=True,timeout=20)
