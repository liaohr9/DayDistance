#!/usr/bin/env python3
"""Disposable sandboxed Sparkle update test; never launches/replaces the real app."""
import functools,http.server,os,plistlib,shutil,subprocess,tempfile,threading,json,time,re
from pathlib import Path
p=Path(__file__).resolve().parent.parent
tools=p/'build.noindex/SparkleTools'; framework=tools/'Sparkle.framework'
env=dict(os.environ)
root=Path(tempfile.mkdtemp(prefix='daydistance-update-qa-',suffix='.noindex'))
(root/'data').mkdir();(root/'data/events.json').write_text('{"sentinel":"keep this temporary data"}')
class Server(http.server.ThreadingHTTPServer): daemon_threads=True
server=Server(('127.0.0.1',0),functools.partial(http.server.SimpleHTTPRequestHandler,directory=str(root)))
threading.Thread(target=server.serve_forever,daemon=True).start()
port=server.server_address[1];bundle_id='local.daydistance.updateqa.'+root.name.split('-')[-1].replace('.noindex','')
public_key=plistlib.loads((p/'Config/App-Info.plist').read_bytes())['SUPublicEDKey']
source=root/'main.swift'
source.write_text('''import SwiftUI
import AppKit
@main struct UpdateQAApp: App {
    @State private var updates = UpdateController.production()
    @State private var editing = false
    var body: some Scene {
        Window("DayDistance Update Test", id: "main") {
            VStack(alignment: .leading, spacing: 20) {
                Text("Sandboxed Update Test").font(.title2)
                Text("Version " + (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"))
                Toggle("Editing a draft", isOn: $editing)
                TextField("Draft", text: .constant("Keep my draft"))
                Toggle("Automatically Check for Updates", isOn: Binding(get: { updates.automaticChecksEnabled }, set: { updates.automaticChecksEnabled = $0 }))
                Button("Check for Updates…") { updates.checkForUpdates() }.disabled(!updates.canCheck || editing)
                if updates.isWaitingToInstall { Text("Waiting for editing to finish") }
                if let error = updates.errorMessage { Text(error) }
            }.padding(30).frame(width: 430)
             .task { updates.start { !editing } }
        }
    }
}
''')
app=root/'current/UpdateQA.app';future=root/'next/UpdateQA.app'
for path,version in [(app,'1'),(future,'2')]:
 c=path/'Contents';(c/'MacOS').mkdir(parents=True);(c/'Frameworks').mkdir()
 subprocess.run(['ditto',str(framework),str(c/'Frameworks/Sparkle.framework')],check=True)
 info={'CFBundleIdentifier':bundle_id,'CFBundleExecutable':'UpdateQA','CFBundleName':'UpdateQA','CFBundlePackageType':'APPL','CFBundleShortVersionString':'0.0.'+version,'CFBundleVersion':version,'LSMinimumSystemVersion':'14.0','SUFeedURL':f'http://127.0.0.1:{port}/appcast.xml','SUPublicEDKey':public_key,'SUEnableAutomaticChecks':False,'SUAllowsAutomaticUpdates':False,'SUEnableInstallerLauncherService':True,'SUVerifyUpdateBeforeExtraction':True,'SURequireSignedFeed':True,'NSAppTransportSecurity':{'NSAllowsLocalNetworking':True}}
 (c/'Info.plist').write_bytes(plistlib.dumps(info))
 if version=='1':
  subprocess.run(['xcrun','swiftc','-parse-as-library','-target','arm64-apple-macos14.0','-F',str(tools),'-framework','Sparkle','-Xlinker','-rpath','-Xlinker','@executable_path/../Frameworks',str(p/'Shared/Core/L10n.swift'),str(p/'App/Services/UpdateController.swift'),str(p/'App/Services/SparkleUpdateClient.swift'),str(source),'-o',str(c/'MacOS/UpdateQA')],env=env,check=True)
 else:shutil.copy2(app/'Contents/MacOS/UpdateQA',c/'MacOS/UpdateQA')
 ent=root/'qa.entitlements';ent.write_bytes(plistlib.dumps({'com.apple.security.app-sandbox':True,'com.apple.security.network.client':True,'com.apple.security.temporary-exception.mach-lookup.global-name':[bundle_id+'-spks',bundle_id+'-spki']}))
 subprocess.run(['codesign','--force','--sign','-','--entitlements',str(ent),str(path)],check=True)
zipfile=root/'UpdateQA.zip';subprocess.run(['ditto','-c','-k','--sequesterRsrc','--keepParent',str(future),str(zipfile)],check=True)
signature=subprocess.check_output([str(tools/'bin/sign_update'),'--account','local.daydistance.mac.updates',str(zipfile)],text=True).strip()
(root/'appcast.xml').write_text(f'''<?xml version="1.0" encoding="utf-8"?><rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><title>Disposable update test</title><item><title>UpdateQA 0.0.2</title><sparkle:version>2</sparkle:version><sparkle:shortVersionString>0.0.2</sparkle:shortVersionString><description>Temporary sandboxed installation test. Real events remain untouched.</description><enclosure url="http://127.0.0.1:{port}/UpdateQA.zip" {signature} type="application/octet-stream"/></item></channel></rss>''')
subprocess.run([str(tools/'bin/sign_update'),'--account','local.daydistance.mac.updates',str(root/'appcast.xml')],check=True)
print('QA_ROOT: '+str(root),flush=True);print('QA_APP: '+str(app),flush=True)
print('QA_BUNDLE: '+bundle_id,flush=True)
subprocess.run(['open',str(app)],check=True)
try:
 while True:time.sleep(1)
except KeyboardInterrupt:pass
finally:server.shutdown();print('QA artifacts retained for readback: '+str(root),flush=True)
