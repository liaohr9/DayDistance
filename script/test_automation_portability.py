"""Check developer selection before any build runs, using a different selected Xcode."""
import os,subprocess,tempfile,unittest
from pathlib import Path
p=Path(__file__).resolve().parent.parent
class PortabilityTests(unittest.TestCase):
 def test_selected_xcode_without_external_disk(self):
  with tempfile.TemporaryDirectory() as folder:
   root=Path(folder);selected=root/'Selected Xcode/Contents/Developer';selected.mkdir(parents=True)
   tool=root/'xcode-select';tool.write_text('#!/bin/sh\nprintf "%s\\n" "'+str(selected)+'"\n');tool.chmod(0o755)
   env=dict(os.environ,PATH=str(root)+':'+os.environ['PATH']);env.pop('DEVELOPER_DIR',None)
   prefix='\n'.join((p/'script/build_and_run.sh').read_text().splitlines()[:7])
   result=subprocess.run(['/bin/bash','-c',prefix+'\nprintf "%s" "$DEVELOPER_DIR"'],env=env,text=True,capture_output=True,check=True)
   self.assertEqual(result.stdout,str(selected))
 def test_compile_entrypoints_do_not_override_selected_xcode(self):
  # When omitted, xcrun honors the selected Xcode; explicit overrides must be caller-owned.
  for name in ['test_widget_intent.py','test_ui_probe_control.py','run_ui_probe.py','test_automation.py','automation_ui_probe.py']:
   source=(p/'script'/name).read_text()
   self.assertNotIn('/Volumes/',source,name)
if __name__=='__main__':unittest.main()
