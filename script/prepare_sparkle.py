#!/usr/bin/env python3
"""Prepare the embedded, pinned Sparkle framework; never touches cached packages."""
import argparse,plistlib,shutil,subprocess
from pathlib import Path

def prepare(framework: Path, identity: str):
    framework=framework.resolve(strict=False)
    if (framework.name != 'Sparkle.framework' or 'build.noindex' not in framework.parts
            or framework.parent.name != 'Frameworks' or framework.parent.parent.name != 'Contents'
            or framework.parent.parent.parent.suffix != '.app'):
        raise ValueError('Only the embedded build.noindex app framework may be modified')
    relative=['Sparkle','Autoupdate','Updater.app/Contents/MacOS/Updater','XPCServices/Installer.xpc/Contents/MacOS/Installer']
    def universal(folder: Path) -> bool:
        info=plistlib.loads((folder/'Versions/B/Resources/Info.plist').read_bytes())
        if info.get('CFBundleShortVersionString') != '2.10.0':
            raise ValueError('Review preparation when upgrading Sparkle')
        for name in relative:
            binary=folder/'Versions/B'/name
            if not binary.exists(): return False
            if not binary.resolve(strict=True).is_relative_to(folder.resolve(strict=True)):
                raise ValueError('Updater executable escapes framework')
            if set(subprocess.check_output(['lipo','-archs',str(binary)],text=True).split()) != {'arm64','x86_64'}:
                return False
        return True
    # Recover missing products and earlier arm-only embedded copies from the
    # pinned sibling build product. Validate the source before changing anything.
    if not framework.exists() or not universal(framework):
        source=framework.parents[3]/'Sparkle.framework'
        if source.is_symlink(): raise ValueError('Unexpected framework build-product symlink')
        if not universal(source): raise ValueError('Sparkle requires arm64 and x86_64')
        framework.parent.mkdir(parents=True,exist_ok=True)
        if framework.exists(): shutil.rmtree(framework)
        shutil.copytree(source,framework,symlinks=True)
    if not universal(framework): raise ValueError('Embedded Sparkle requires arm64 and x86_64')
    base=framework/'Versions/B'
    # The app has outgoing network access; Sparkle explicitly does not need Downloader.xpc.
    downloader=base/'XPCServices/Downloader.xpc'
    if downloader.exists(): shutil.rmtree(downloader)
    for path in [base/'XPCServices/Installer.xpc',base/'Autoupdate',base/'Updater.app',framework]:
        command=['codesign','--force','--sign',identity or '-', '--options','runtime']
        if identity and identity != '-':command.append('--timestamp')
        subprocess.run(command+[str(path)],check=True)
    subprocess.run(['codesign','--verify','--deep','--strict','--all-architectures',str(framework)],check=True)

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('framework',type=Path);parser.add_argument('--identity',default='-')
    args=parser.parse_args();prepare(args.framework,args.identity)
