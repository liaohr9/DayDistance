#!/usr/bin/env python3
"""Prepare a signed GitHub update ZIP and appcast locally; never uploads or exports keys."""
import argparse,base64,hashlib,html,json,plistlib,re,shutil,subprocess,tempfile,xml.etree.ElementTree as ET
from pathlib import Path
ACCOUNT='local.daydistance.mac.updates'
PREFIX='https://github.com/liaohr9/DayDistance/releases/download/'

def release_catalog():
    document=json.loads((Path(__file__).resolve().parent.parent/'Shared/Core/Resources/release-history.json').read_text())
    entries=document['releases']
    if document['schemaVersion']!=1 or not entries or len({e['version'] for e in entries})!=len(entries):
        raise ValueError('Invalid release history')
    if [e['build'] for e in entries]!=sorted({e['build'] for e in entries},reverse=True):
        raise ValueError('Release history must have unique descending builds')
    for entry in entries:
        for section in entry['sections']:
            if section['kind'] not in {'added','improved','fixed'} or not section['items']: raise ValueError('Invalid release section')
            for item in section['items']:
                if any(not item[lang].strip() for lang in ['en','zh-Hans']): raise ValueError('Missing translation')
    return entries

def release_notes(version, build):
    entry=next((e for e in release_catalog() if e['version']==version and str(e['build'])==str(build)),None)
    if entry is None: raise ValueError('Release notes must match the packaged version and build')
    labels={'en':{'added':'New','improved':'Improvements','fixed':'Fixes'},'zh-Hans':{'added':'新增','improved':'改进','fixed':'修复'}}
    return {lang:'<h2>'+html.escape(version)+'</h2>'+''.join('<h3>'+labels[lang][s['kind']]+'</h3><ul>'+''.join('<li>'+html.escape(i[lang])+'</li>' for i in s['items'])+'</ul>' for s in entry['sections'])+'<p>'+('Developer preview. Not notarized by Apple.' if lang=='en' else '开发预览版，尚未经过 Apple 公证。')+'</p>' for lang in labels}

def embed_notes(feed, notes):
    ET.register_namespace('sparkle','http://www.andymatuschak.org/xml-namespaces/sparkle')
    tree=ET.parse(feed);item=tree.find('./channel/item')
    if item is None: raise ValueError('Missing current release')
    for old in item.findall('description'): item.remove(old)
    ET.SubElement(item,'description').text=notes['en']
    for lang,body in notes.items(): ET.SubElement(item,'description',{'{http://www.w3.org/XML/1998/namespace}lang':lang}).text=body
    ET.SubElement(item,'{http://www.andymatuschak.org/xml-namespaces/sparkle}fullReleaseNotesLink').text='https://github.com/liaohr9/DayDistance/releases'
    tree.write(feed,encoding='utf-8',xml_declaration=True)

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

def validate_architectures(app: Path):
    """All update executables must support arm64 and x86_64, including helpers."""
    app=app.resolve(strict=True)
    binaries=[]
    for bundle in [app,app/'Contents/PlugIns/DayDistanceWidget.appex']:
        info=plistlib.loads((bundle/'Contents/Info.plist').read_bytes())
        binaries.append(bundle/'Contents/MacOS'/info['CFBundleExecutable'])
    base=app/'Contents/Frameworks/Sparkle.framework/Versions/B'
    binaries.extend(base/name for name in ['Sparkle','Autoupdate','Updater.app/Contents/MacOS/Updater','XPCServices/Installer.xpc/Contents/MacOS/Installer'])
    for binary in binaries:
        if not binary.resolve(strict=True).is_relative_to(app):
            raise ValueError('Executable escapes application: '+str(binary))
        architectures=subprocess.check_output(['lipo','-archs',str(binary)],text=True,timeout=30).split()
        if set(architectures)!={'arm64','x86_64'}:
            raise ValueError('Update packages require arm64 and x86_64: '+str(binary))

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('app',type=Path);parser.add_argument('--output',required=True,type=Path);parser.add_argument('--tag',required=True);parser.add_argument('--sparkle-tools',required=True,type=Path);parser.add_argument('--preview',action='store_true');parser.add_argument('--team');parser.add_argument('--group')
    args=parser.parse_args();app=args.app.resolve(strict=True);info=plistlib.loads((app/'Contents/Info.plist').read_bytes())
    if not re.fullmatch(r'v[0-9]+\.[0-9]+\.[0-9]+(?:-[A-Za-z0-9.-]+)?',args.tag):raise ValueError('Expected a version release tag')
    if args.tag.split('-')[0]!='v'+info['CFBundleShortVersionString']:raise ValueError('Tag must match the app version')
    if info.get('CFBundleIdentifier')!='local.daydistance.mac' or not info.get('SURequireSignedFeed'):raise ValueError('Expected configured DayDistance updater')
    if args.preview:
        if '-preview.' not in args.tag or info.get('DayDistanceStorageMode')!='local':raise ValueError('Preview must have explicit preview tag and local storage')
    else:
        if info.get('SUFeedURL') == 'https://raw.githubusercontent.com/liaohr9/DayDistance/main/appcast.xml':
            raise ValueError('This feed upgrades local-storage previews only. Formal App Group migration and a separate feed must be accepted first')
        import prepare_release
        result=prepare_release.checked(app,args.team or '',args.group or '', 'distribution')
        if not result['distributable']:raise ValueError('Developer ID, notarization and shared storage validation required')
    notes=release_notes(info['CFBundleShortVersionString'],info['CFBundleVersion'])
    output=args.output.resolve()
    if output.is_relative_to(app):raise ValueError('Output must be separate from the source application')
    if output.exists():raise FileExistsError('Use a new output directory; never overwrite a release')
    for f in app.rglob('*'):
        if f.name=='events.json':raise ValueError('User data must never be packaged')
    validate_architectures(app)
    subprocess.run(['codesign','--verify','--deep','--strict','--all-architectures',str(app)],check=True)
    tools=args.sparkle_tools.resolve()/ 'bin'
    key=subprocess.check_output([str(tools/'generate_keys'),'--account',ACCOUNT,'-p'],text=True).strip()
    if key!=info.get('SUPublicEDKey'):raise ValueError('Signing account does not match embedded public key')
    output.mkdir(parents=True)
    archive=output/('DayDistance-'+info['CFBundleShortVersionString']+'-macOS-universal'+('-preview' if args.preview else '')+'.zip')
    with tempfile.TemporaryDirectory(suffix='.noindex') as tmp:
        staged=Path(tmp)/'日距.app';subprocess.run(['ditto',str(app),str(staged)],check=True)
        subprocess.run(['ditto','-c','-k','--sequesterRsrc','--keepParent',str(staged),str(archive)],check=True)
    subprocess.run([str(tools/'generate_appcast'),'--account',ACCOUNT,'--maximum-deltas','0','--download-url-prefix',PREFIX+args.tag+'/',str(output)],check=True)
    feed=output/'appcast.xml'
    embed_notes(feed,notes)
    subprocess.run([str(tools/'sign_update'),'--account',ACCOUNT,str(feed)],check=True)
    signature=validate_feed(feed,archive,args.tag,info)
    subprocess.run([str(tools/'sign_update'),'--account',ACCOUNT,'--verify',str(archive),signature],check=True)
    subprocess.run([str(tools/'sign_update'),'--account',ACCOUNT,'--verify',str(feed)],check=True)
    manifest={'version':info['CFBundleShortVersionString'],'build':info['CFBundleVersion'],'tag':args.tag,'preview':args.preview,'notarized':not args.preview,'architectures':['arm64','x86_64'],'archive':archive.name,'bytes':archive.stat().st_size,'sha256':hashlib.sha256(archive.read_bytes()).hexdigest(),'updateSignatureVerified':True,'feedSignatureVerified':True}
    (output/'UPDATE_INFO.json').write_text(json.dumps(manifest,indent=2)+'\n');print(json.dumps(manifest,indent=2))

if __name__=='__main__':main()
