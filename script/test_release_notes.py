"""Release catalog validation and safe feed-note rendering, with no signing or network."""
import importlib.util
import unittest
import tempfile
import xml.etree.ElementTree as ET
from pathlib import Path
spec = importlib.util.spec_from_file_location('prepare_update', Path(__file__).with_name('prepare_update.py'))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
class NotesTests(unittest.TestCase):
    def test_version_is_exact_and_missing_version_blocks_packaging(self):
        notes = module.release_notes('1.14.0', '43')
        self.assertIn('刷新并修复', notes['zh-Hans'])
        self.assertIn('Release Notes', notes['en'])
        self.assertNotIn('<script', notes['en'])
        with self.assertRaises(ValueError): module.release_notes('9.9.9', '999')
        with self.assertRaises(ValueError): module.release_notes('1.14.0', '42')
    def test_embedded_notes_include_default_and_both_languages(self):
        with tempfile.TemporaryDirectory() as folder:
            feed = Path(folder) / 'appcast.xml'
            feed.write_text('<rss><channel><item><title>1.14.0</title></item></channel></rss>')
            notes = module.release_notes('1.14.0', '43')
            module.embed_notes(feed, notes)
            item = ET.parse(feed).find('./channel/item')
            self.assertEqual(item.findtext('description'), notes['en'])
            translated = {e.get('{http://www.w3.org/XML/1998/namespace}lang'): e.text for e in item.findall('description')}
            self.assertEqual(translated['zh-Hans'], notes['zh-Hans'])
            self.assertEqual(translated['en'], notes['en'])
    def test_catalog_has_unique_ordered_versions_and_no_empty_translations(self):
        entries = module.release_catalog()
        self.assertEqual(len({e['version'] for e in entries}),len(entries))
        self.assertEqual([e['build'] for e in entries],sorted([e['build'] for e in entries],reverse=True))
        for e in entries:
            for s in e['sections']:
                for item in s['items']:
                    self.assertTrue(item['en'].strip()); self.assertTrue(item['zh-Hans'].strip())
if __name__ == '__main__': unittest.main()
