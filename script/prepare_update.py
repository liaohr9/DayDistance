#!/usr/bin/env python3
"""Prepare a signed GitHub update ZIP and appcast locally; never uploads or exports keys."""
import argparse,base64,hashlib,json,plistlib,re,shutil,subprocess,tempfile,xml.etree.ElementTree as ET
from pathlib import Path
ACCOUNT='local.daydistance.mac.updates'
PREFIX='https://github.com/liaohr9/DayDistance/releases/download/'

def validate_feed(feed: Path, archive: Path, tag: str, info: dict):
    ns={'s':'http://www.andymatuschak.org/xml-namespaces/sparkle'}
    items=ET.parse(feed).findall('./channel/item')
    if len(items)!=1:raise ValueError('Expected exactly one current release')
    item=items[0];enclosure=item.find('enclosure')
    if item.findtext('s:version',namespaces=ns)!=info['CFBundleVersion']:raise ValueError('Wrong build version')
    if enclosure is None or enclosure.get('url')!=PREFIX+tag+'/'+archive.name:raise ValueError('Unexpected download URL')
    if enclosure.get('length')!=str(archive.stat().st_size):raise ValueError('Archive length mismatch')
    signature=enclosure.get('{'+ns['s']+'}edSignature','')
    if len(base64.b64decode(signature,validate=True))!=64:raise ValueError('Archive signature missing')
    return signature

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('app',type=Path);parser.add_argument('--output',required=True,type=Path);parser.add_argument('--tag',required=True);parser.add_argument('--sparkle-tools',required=True,type=Path);parser.add_argument('--preview',action='store_true');parser.add_argument('--team');parser.add_argument('--group')
    args=parser.parse_args();app=args.app.resolve(strict=True);info=plistlib.loads((app/'Contents/Info.plist').read_bytes())
    if not re.fullmatch(r'v[0-9]+\.[0-9]+\.[0-9]+(?:-[A-Za-z0-9.-]+)?',args.tag):raise ValueError('Expected a version release tag')
    if args.tag.split('-')[0]!='v'+info['CFBundleShortVersionString']:raise ValueError('Tag must match the app version')
    if info.get('CFBundleIdentifier')!='local.daydistance.mac' or not info.get('SURequireSignedFeed'):raise ValueError('Expected configured DayDistance updater')
    if args.preview:
        if '-preview.' not in args.tag or info.get('DayDistanceStorageMode')!='local':raise ValueError('Preview must have explicit preview tag and local storage')
    else:
        import prepare_release
        result=prepare_release.checked(app,args.team or '',args.group or '', 'distribution')
        if not result['distributable']:raise ValueError('Developer ID, notarization and shared storage validation required')
    output=args.output.resolve()
    if output.is_relative_to(app):raise ValueError('Output must be separate from the source application')
    if output.exists():raise FileExistsError('Use a new output directory; never overwrite a release')
    for f in app.rglob('*'):
        if f.name=='events.json':raise ValueError('User data must never be packaged')
    subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)
    tools=args.sparkle_tools.resolve()/ 'bin'
    key=subprocess.check_output([str(tools/'generate_keys'),'--account',ACCOUNT,'-p'],text=True).strip()
    if key!=info.get('SUPublicEDKey'):raise ValueError('Signing account does not match embedded public key')
    output.mkdir(parents=True)
    archive=output/('DayDistance-'+info['CFBundleShortVersionString']+'-macOS-arm64'+('-preview' if args.preview else '')+'.zip')
    with tempfile.TemporaryDirectory(suffix='.noindex') as tmp:
        staged=Path(tmp)/'日距.app';subprocess.run(['ditto',str(app),str(staged)],check=True)
        subprocess.run(['ditto','-c','-k','--sequesterRsrc','--keepParent',str(staged),str(archive)],check=True)
    subprocess.run([str(tools/'generate_appcast'),'--account',ACCOUNT,'--maximum-deltas','0','--download-url-prefix',PREFIX+args.tag+'/',str(output)],check=True)
    feed=output/'appcast.xml';signature=validate_feed(feed,archive,args.tag,info)
    subprocess.run([str(tools/'sign_update'),'--account',ACCOUNT,'--verify',str(archive),signature],check=True)
    subprocess.run([str(tools/'sign_update'),'--account',ACCOUNT,'--verify',str(feed)],check=True)
    manifest={'version':info['CFBundleShortVersionString'],'build':info['CFBundleVersion'],'tag':args.tag,'preview':args.preview,'notarized':not args.preview,'archive':archive.name,'bytes':archive.stat().st_size,'sha256':hashlib.sha256(archive.read_bytes()).hexdigest(),'updateSignatureVerified':True,'feedSignatureVerified':True}
    (output/'UPDATE_INFO.json').write_text(json.dumps(manifest,indent=2)+'\n');print(json.dumps(manifest,indent=2))

if __name__=='__main__':main()
