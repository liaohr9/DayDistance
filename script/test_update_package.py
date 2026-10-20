"""Reject non-arm64 or escaping code before preparing a preview update."""
import importlib.util,plistlib,tempfile,unittest
from pathlib import Path
from unittest.mock import patch
spec=importlib.util.spec_from_file_location('prepare_update',Path(__file__).with_name('prepare_update.py'))
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
class PackageArchitectureTests(unittest.TestCase):
    def fixture(self, root):
        app=Path(root)/'DayDistance.app'
        for bundle,identifier,executable in [(app,'local.daydistance.mac','DayDistance'),(app/'Contents/PlugIns/DayDistanceWidget.appex','local.daydistance.mac.widget','DayDistanceWidget')]:
            (bundle/'Contents/MacOS').mkdir(parents=True)
            (bundle/'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':identifier,'CFBundleExecutable':executable}))
            (bundle/'Contents/MacOS'/executable).write_bytes(b'fixture')
        for name in ['Sparkle','Autoupdate','Updater.app/Contents/MacOS/Updater','XPCServices/Installer.xpc/Contents/MacOS/Installer']:
            f=app/'Contents/Frameworks/Sparkle.framework/Versions/B'/name
            f.parent.mkdir(parents=True,exist_ok=True);f.write_bytes(b'fixture')
        return app
    def test_all_six_executables_are_checked(self):
        with tempfile.TemporaryDirectory() as root:
            app=self.fixture(root)
            with patch.object(module.subprocess,'check_output',return_value='arm64') as call:
                module.validate_architectures(app)
            self.assertEqual(call.call_count,6)
    def test_universal_updater_is_rejected(self):
        with tempfile.TemporaryDirectory() as root:
            app=self.fixture(root)
            def architectures(args,**kwargs):
                return 'x86_64 arm64' if Path(args[-1]).name=='Sparkle' else 'arm64'
            with patch.object(module.subprocess,'check_output',side_effect=architectures),self.assertRaisesRegex(ValueError,'arm64'):
                module.validate_architectures(app)
    def test_intel_widget_is_rejected(self):
        with tempfile.TemporaryDirectory() as root:
            app=self.fixture(root)
            def architectures(args,**kwargs):
                return 'x86_64' if Path(args[-1]).name=='DayDistanceWidget' else 'arm64'
            with patch.object(module.subprocess,'check_output',side_effect=architectures),self.assertRaisesRegex(ValueError,'arm64'):
                module.validate_architectures(app)
    def test_missing_updater_is_rejected(self):
        with tempfile.TemporaryDirectory() as root:
            app=self.fixture(root)
            (app/'Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate').unlink()
            with patch.object(module.subprocess,'check_output',return_value='arm64'),self.assertRaises(FileNotFoundError):
                module.validate_architectures(app)
    def test_escaping_executable_is_rejected(self):
        with tempfile.TemporaryDirectory() as root:
            app=self.fixture(root);outside=Path(root)/'outside';outside.write_bytes(b'outside')
            f=app/'Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate';f.unlink();f.symlink_to(outside)
            with patch.object(module.subprocess,'check_output',return_value='arm64'),self.assertRaisesRegex(ValueError,'escape'):
                module.validate_architectures(app)
if __name__=='__main__':unittest.main()
