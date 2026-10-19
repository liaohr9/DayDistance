#!/usr/bin/env python3
"""Run the production app/CLI in a signed sandbox with disposable in-container data."""
import os,plistlib,subprocess
from pathlib import Path
env = dict(os.environ)
p=Path(__file__).resolve().parent.parent
root=p/'Validation/automation/qa.noindex'
root.mkdir(parents=True,exist_ok=True)
app=root/'Automation QA.app'
contents=app/'Contents';(contents/'MacOS').mkdir(parents=True,exist_ok=True)
s=(p/'Shared/Platform/SharedContainer.swift').read_text()
a=s.index('    static func repository()');b=s.index('    static func smartListFileURL()',a)
s=s[:a]+'''    static func repository() throws -> EventRepository {
        let support=try FileManager.default.url(for:.applicationSupportDirectory,in:.userDomainMask,appropriateFor:nil,create:true)
        return EventRepository(fileURL:support.appendingPathComponent("AutomationQA/events.json"))
    }
'''+s[b:]
shared=root/'SharedContainer.swift';shared.write_text(s)
sources=sorted((p/'Shared/Core').glob('*.swift'))+sorted((p/'Shared/Presentation').glob('*.swift'))+[shared]+sorted((p/'App/Stores').glob('*.swift'))+sorted((p/'App/Views').glob('*.swift'))+sorted((p/'App/Services').glob('*.swift'))+sorted((p/'App/Intents').glob('*.swift'))+[p/'App/DayDistanceApp.swift']
subprocess.run(['xcrun','swiftc','-parse-as-library','-target','arm64-apple-macos14.0',*map(str,sources),'-o',str(contents/'MacOS/DayDistance')],env=env,check=True,timeout=180)
info=plistlib.loads((p/'Config/App-Info.plist').read_bytes())
info.update(CFBundleIdentifier='local.dd.agentqa',CFBundleExecutable='DayDistance',CFBundleName='日距自动化验证',CFBundleDisplayName='日距自动化验证',CFBundleShortVersionString='1.15.0',CFBundleVersion='44',LSMinimumSystemVersion='14.0',DayDistanceStorageMode='qa',LSUIElement=False)
(contents/'Info.plist').write_bytes(plistlib.dumps(info))
for lang in ['en','zh-Hans']:
 import shutil
 shutil.copytree(p/f'Shared/Core/Resources/{lang}.lproj',contents/f'Resources/{lang}.lproj',dirs_exist_ok=True)
shutil.copy(p/'Shared/Core/Resources/release-history.json',contents/'Resources/release-history.json')
entitlements=root/'qa.entitlements'
entitlements.write_bytes(plistlib.dumps({'com.apple.security.app-sandbox':True,'com.apple.security.network.client':True,'com.apple.security.files.user-selected.read-write':True}))
subprocess.run(['codesign','--force','--sign','-','--entitlements',str(entitlements),str(app)],check=True)
print(app,flush=True)
