#!/usr/bin/env python3
"""Prepare the embedded, pinned Sparkle framework; never touches cached packages."""
import argparse,os,plistlib,shutil,subprocess,tempfile
from pathlib import Path

def prepare(framework: Path, identity: str):
    framework=framework.resolve(strict=False)
    if (framework.name != 'Sparkle.framework' or 'build.noindex' not in framework.parts
            or framework.parent.name != 'Frameworks' or framework.parent.parent.name != 'Contents'
            or framework.parent.parent.parent.suffix != '.app'):
        raise ValueError('Only the embedded build.noindex app framework may be modified')
    # The guarded installer removes its unindexed candidate after installation.
    # Xcode can retain a successful copy-phase record for that missing product.
    # Recover only the pinned sibling build product, never alter the package cache.
    if not framework.exists():
        source=framework.parents[3]/'Sparkle.framework'
        if source.is_symlink(): raise ValueError('Unexpected framework build-product symlink')
        info=plistlib.loads((source/'Versions/B/Resources/Info.plist').read_bytes())
        if info.get('CFBundleShortVersionString') != '2.10.0':
            raise ValueError('Review preparation when upgrading Sparkle')
        framework.parent.mkdir(parents=True,exist_ok=True)
        shutil.copytree(source,framework,symlinks=True)
    framework=framework.resolve(strict=True)
    if 'build.noindex' not in framework.parts or framework.parent.name != 'Frameworks':
        raise ValueError('Unexpected embedded framework destination')
    base=framework/'Versions/B'
    info=plistlib.loads((base/'Resources/Info.plist').read_bytes())
    if info.get('CFBundleShortVersionString') != '2.10.0': raise ValueError('Review preparation when upgrading Sparkle')
    # The app has outgoing network access; Sparkle explicitly does not need Downloader.xpc.
    downloader=base/'XPCServices/Downloader.xpc'
    if downloader.exists(): shutil.rmtree(downloader)
    relative=['Sparkle','Autoupdate','Updater.app/Contents/MacOS/Updater','XPCServices/Installer.xpc/Contents/MacOS/Installer']
    for name in relative:
        binary=base/name
        architectures=subprocess.check_output(['lipo','-archs',str(binary)],text=True).split()
        if architectures != ['arm64']:
            if 'arm64' not in architectures: raise ValueError('Missing arm64: '+name)
            with tempfile.TemporaryDirectory(dir=binary.parent) as folder:
                thin=Path(folder)/binary.name
                subprocess.run(['lipo',str(binary),'-thin','arm64','-output',str(thin)],check=True)
                thin.chmod(binary.stat().st_mode);os.replace(thin,binary)
    for path in [base/'XPCServices/Installer.xpc',base/'Autoupdate',base/'Updater.app',framework]:
        command=['codesign','--force','--sign',identity or '-', '--options','runtime']
        if identity and identity != '-':command.append('--timestamp')
        subprocess.run(command+[str(path)],check=True)
    subprocess.run(['codesign','--verify','--deep','--strict',str(framework)],check=True)

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('framework',type=Path);parser.add_argument('--identity',default='-')
    args=parser.parse_args();prepare(args.framework,args.identity)
