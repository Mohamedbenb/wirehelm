"""Exercise the production SQLite schema/query with Android's string binding semantics."""
import re
import sqlite3
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path

SOURCE = (Path(__file__).resolve().parents[1] / 'android/app/src/main/kotlin/com/example/remote_control/clipboard/ClipboardShelfStore.kt').read_text(encoding='utf-8')
SCHEMA = re.search(r'db.execSQL\("(CREATE TABLE clips[^"\n]+)"\)', SOURCE).group(1)
LIST = re.search(r'rawQuery\("(SELECT id,kind,text,source,stamp,pinned,image,thumb,mime FROM clips WHERE \(\?[^"\n]+)"', SOURCE).group(1)

LIMIT = re.search(r'execSQL\(\"(DELETE FROM clips WHERE pinned=0 AND id NOT IN[^\"\n]+)\"', SOURCE).group(1)
EXPIRE = re.search(r'delete\(\"clips\",\"(pinned=0 AND stamp<\?)\"', SOURCE).group(1)

class ShelfSqlTest(unittest.TestCase):
    def setUp(self):
        self.db = sqlite3.connect(':memory:')
        self.db.execute(SCHEMA)
        self.db.executemany('INSERT INTO clips(hash,kind,text,source,stamp,pinned) VALUES(?,?,?,?,?,?)', [
            ('text:a','text','ordinary sample','com.example.one',1,0),
            ('text:b','text','pinned sample','com.example.two',2,1),
            ('text:c','text','literal %_ and العربية','com.example.three',3,0)])
    def tearDown(self):
        self.db.close()
    def rows(self, query='', pinned=False):
        return list(self.db.execute(LIST,(query,query,query,'1' if pinned else '0')))
    def test_unpinned_entries_are_visible_with_string_bound_zero(self):
        self.assertEqual([r[0] for r in self.rows()],[2,3,1])
    def test_pin_filter_keeps_only_pins(self):
        self.assertEqual([r[0] for r in self.rows(pinned=True)],[2])
    def test_recent_limit_keeps_pins_outside_the_limit(self):
        self.db.execute(LIMIT.replace('${p.limit}', '1'))
        self.assertEqual([r[0] for r in self.rows()],[2,3])
    def test_expiry_preserves_old_pins(self):
        self.db.execute('UPDATE clips SET stamp=0 WHERE pinned=1')
        self.db.execute('DELETE FROM clips WHERE '+EXPIRE, ('2',))
        self.assertEqual([r[0] for r in self.rows()],[2,3])
    def test_search_is_literal_and_reaches_text_and_source(self):
        for query, expected in [('ordinary',[1]),('example.three',[3]),('%_',[3]),('العربية',[3]),('no-match',[])]:
            self.assertEqual([r[0] for r in self.rows(query)],expected)

class ImageProviderManifestTest(unittest.TestCase):
    def test_clipboard_provider_declares_static_file_paths_metadata(self):
        root=Path(__file__).resolve().parents[1]
        manifest=ET.parse(root/'android/app/src/main/AndroidManifest.xml')
        ns='{http://schemas.android.com/apk/res/android}'
        providers=[p for p in manifest.findall('./application/provider') if p.get(ns+'name')=='.clipboard.ClipboardImageProvider']
        self.assertEqual(len(providers),1)
        metadata={m.get(ns+'name'):m.get(ns+'resource') for m in providers[0].findall('meta-data')}
        self.assertEqual(metadata.get('android.support.FILE_PROVIDER_PATHS'),'@xml/clipboard_paths')
        self.assertEqual(providers[0].get(ns+'exported'),'false')
        self.assertEqual(providers[0].get(ns+'grantUriPermissions'),'true')

if __name__ == '__main__':
    unittest.main()
