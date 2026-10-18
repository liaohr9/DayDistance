#!/usr/bin/env python3
import os,subprocess,tempfile
from pathlib import Path
p=Path(__file__).resolve().parent.parent
env=dict(os.environ)
sources=sorted((p/'Shared/Core').glob('*.swift'))+[p/'Shared/Platform/SharedContainer.swift',p/'Shared/Presentation/DayEntry.swift',p/'Widget/EventIntent.swift',p/'Tests/Fixtures/WidgetSmartListProbe.swift']
with tempfile.TemporaryDirectory(suffix='.noindex') as folder:
 binary=Path(folder)/'smart-widget-probe'
 subprocess.run(['xcrun','swiftc','-parse-as-library',*map(str,sources),'-o',str(binary)],env=env,check=True,timeout=120)
 subprocess.run([str(binary)],check=True,timeout=15)
