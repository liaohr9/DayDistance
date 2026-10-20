"""Verify missing-product recovery without modifying the pinned package artifact."""
import importlib.util,plistlib,tempfile,unittest
from pathlib import Path
from unittest.mock import patch
spec=importlib.util.spec_from_file_location('prepare_sparkle',Path(__file__).with_name('prepare_sparkle.py'))
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
class FrameworkRecoveryTests(unittest.TestCase):
    def fixture(self, root, version='2.10.0'):
        products=Path(root)/'build.noindex/Build/Products/DebugLocal'
        source=products/'Sparkle.framework'
        base=source/'Versions/B';(base/'Resources').mkdir(parents=True)
        (base/'Resources/Info.plist').write_bytes(plistlib.dumps({'CFBundleShortVersionString':version}))
        for name in ['Sparkle','Autoupdate','Updater.app/Contents/MacOS/Updater','XPCServices/Installer.xpc/Contents/MacOS/Installer','XPCServices/Downloader.xpc/Contents/MacOS/Downloader']:
            file=base/name;file.parent.mkdir(parents=True,exist_ok=True);file.write_bytes(b'fixture source remains unchanged')
        return source,products/'DayDistance.app/Contents/Frameworks/Sparkle.framework'
    def test_missing_embedded_copy_recovers_from_pinned_sibling_and_preserves_source(self):
        with tempfile.TemporaryDirectory(suffix='.noindex') as root:
            source,target=self.fixture(root)
            with patch.object(module.subprocess,'check_output',return_value='arm64'),patch.object(module.subprocess,'run'):
                module.prepare(target,'-')
            self.assertEqual((target/'Versions/B/Sparkle').read_bytes(),(source/'Versions/B/Sparkle').read_bytes())
            self.assertFalse((target/'Versions/B/XPCServices/Downloader.xpc').exists())
            self.assertTrue((source/'Versions/B/XPCServices/Downloader.xpc').is_dir())
    def test_mismatched_pinned_version_is_rejected_before_copy(self):
        with tempfile.TemporaryDirectory(suffix='.noindex') as root:
            source,target=self.fixture(root,version='9.9.9')
            with self.assertRaises(ValueError):module.prepare(target,'-')
            self.assertFalse(target.exists());self.assertTrue(source.exists())
    def test_refuses_destination_outside_exact_embedded_product(self):
        with tempfile.TemporaryDirectory(suffix='.noindex') as root:
            source,_=self.fixture(root)
            with self.assertRaises(ValueError):module.prepare(source,'-')
            self.assertTrue((source/'Versions/B/XPCServices/Downloader.xpc').exists())
    def test_symlinked_parent_cannot_redirect_recovery_outside_build(self):
        with tempfile.TemporaryDirectory(suffix='.noindex') as root:
            source,target=self.fixture(root)
            outside=Path(root)/'outside';outside.mkdir()
            target.parent.parent.mkdir(parents=True)
            target.parent.symlink_to(outside,target_is_directory=True)
            with self.assertRaises(ValueError):module.prepare(target,'-')
            self.assertEqual(list(outside.iterdir()),[])
if __name__=='__main__':unittest.main()
