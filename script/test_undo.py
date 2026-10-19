#!/usr/bin/env python3
import os
import shutil
from pathlib import Path
env = dict(os.environ)
import subprocess
import tempfile
root = Path(__file__).resolve().parent.parent
with tempfile.TemporaryDirectory(suffix='.noindex') as temporary:
    binary = str(Path(temporary) / 'undo-probe')
    sources = sorted((root/'Shared/Core').glob('*.swift')) + [root/'Shared/Platform/SharedContainer.swift', root/'App/Services/EventHistoryUndoManager.swift', root/'App/Stores/EventStore.swift',root/'Tests/Fixtures/UndoProbe.swift']
    snapshots = []
    for source in sources:
        snapshot = Path(temporary) / 'sources' / source.relative_to(root)
        snapshot.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, snapshot)
        snapshots.append(snapshot)
    subprocess.run(['xcrun','swiftc','-parse-as-library',*map(str,snapshots),'-o',binary],env=env,check=True,timeout=90)
    subprocess.run([binary,temporary],check=True,timeout=15)
