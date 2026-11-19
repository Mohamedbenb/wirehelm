"""Runs production Java patcher against real SQLite through a host-only JDBC adapter.
Requires pinned test jars in build/carrier-host. Android app_process/boot remains a device check.
"""
import base64, json, hashlib, os, sqlite3, subprocess, tempfile, unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
WORK=ROOT/'build/carrier-host'
JDK=Path(os.environ.get('JAVA_HOME','C:/Program Files/Android/Android Studio/jbr'))
PROFILE='a'*40
class CarrierDatabaseTest(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  cls.classes=WORK/'classes';cls.classes.mkdir(exist_ok=True)
  jars=[WORK/'sqlite-jdbc.jar',WORK/'slf4j-api.jar']
  cls.cp=os.pathsep.join(map(str,[cls.classes,*jars]))
  sources=[ROOT/'scripts/carrier/CarrierDatabaseTool.java',*sorted((ROOT/'test/carrier_host').rglob('*.java'))]
  subprocess.run([str(JDK/'bin/javac.exe'),'-encoding','UTF-8','--release','17','-classpath',os.pathsep.join(map(str,jars)),'-d',str(cls.classes),*map(str,sources)],check=True)
 def setUp(self):
  self.tmp=tempfile.TemporaryDirectory();self.addCleanup(self.tmp.cleanup);self.dir=Path(self.tmp.name);self.base=self.dir/'vendor.db';self.state=self.dir/'state'
 def fixture(self):
  c=sqlite3.connect(self.base)
  c.executescript('CREATE TABLE confnames(carrier_id INTEGER,name TEXT);CREATE TABLE confmap(carrier_id TEXT PRIMARY KEY,parent_id TEXT,confman TEXT);CREATE TABLE carrier_info(carrier_id INTEGER,mccmnc TEXT);CREATE TABLE confman_'+PROFILE+'(confseq TEXT);CREATE TABLE untouched(i INTEGER,t TEXT,b BLOB,n);')
  c.execute('INSERT INTO confnames VALUES(?,?)',(99009,'wildcard_5g'));c.execute('INSERT INTO confmap VALUES(?,?,?)',('99009',None,PROFILE));c.execute('INSERT INTO confman_'+PROFILE+' VALUES(?)',('current-firmware-sequence',))
  c.executemany('INSERT INTO carrier_info VALUES(?,?)',[(7001,'60502'),(8002,'60501')]);c.execute('INSERT INTO confmap VALUES(?,?,?)',('7001','parent-kept','b'*40));c.execute('INSERT INTO untouched VALUES(?,?,?,?)',(7,'case Sensitive',b'\x00\xff',None));c.commit();c.close()
 def run_tool(self,ok=True,mode='prepare'):
  before=self.base.read_bytes()
  p=subprocess.run([str(JDK/'bin/java.exe'),'-XX:TieredStopAtLevel=1','-cp',self.cp,'com.nodecockpit.carrier.CarrierDatabaseTool',mode,str(self.base),str(self.state),'60502,60501'],capture_output=True,text=True)
  self.assertEqual(p.returncode==0,ok,p.stdout+p.stderr)
  self.assertEqual(before,self.base.read_bytes(),'Vendor input mutated')
  return p
 def test_dynamic_ids_profile_and_parent_preserved(self):
  self.fixture();self.run_tool();c=sqlite3.connect(self.state/'patched.db')
  self.assertEqual(c.execute('select * from confmap where carrier_id=7001').fetchone(),('7001','parent-kept',PROFILE))
  self.assertEqual(c.execute('select confman from confmap where carrier_id=8002').fetchone(),(PROFILE,))
  self.assertEqual(c.execute('select * from untouched').fetchone(),(7,'case Sensitive',b'\x00\xff',None))
  backup=self.state/'stock-backups'/(hashlib.sha256(self.base.read_bytes()).hexdigest()+'.db');self.assertEqual(backup.read_bytes(),self.base.read_bytes());c.close()
 def test_missing_profile_refuses_without_replacing_good_state(self):
  self.fixture();self.state.mkdir();manifest=self.state/'prepared.properties';manifest.write_text('previous-good-state')
  c=sqlite3.connect(self.base);c.execute('delete from confnames');c.commit();c.close();self.run_tool(False);self.assertEqual(manifest.read_text(),'previous-good-state')
 def test_ambiguous_identity_refused(self):
  self.fixture();c=sqlite3.connect(self.base);c.execute('insert into carrier_info values(9999,"60502")');c.commit();c.close();self.run_tool(False)
 def test_schema_change_refused(self):
  self.fixture();c=sqlite3.connect(self.base);c.execute('alter table confmap add column changed_schema TEXT');c.commit();c.close();self.run_tool(False)
 def test_trigger_mutation_refused(self):
  self.fixture();c=sqlite3.connect(self.base);c.execute('create trigger bad after update on confmap begin delete from untouched; end');c.commit();c.close();self.run_tool(False);self.assertFalse((self.state/'prepared.properties').exists())
 def test_inspect_has_no_preparation_side_effects(self):
  self.fixture();self.run_tool(mode='inspect');self.assertFalse(self.state.exists())
 def test_stale_sqlite_sidecars_do_not_replay_into_new_copy(self):
  self.fixture();self.state.mkdir()
  for name in ('stock.db.tmp-journal','stock.db.tmp-wal','patched.db.tmp-journal','patched.db.tmp-wal','patched.db.tmp-shm'):(self.state/name).write_bytes(b'previous interrupted preparation')
  self.run_tool()
  self.assertFalse((self.state/'stock.db.tmp-journal').exists())
  self.assertFalse((self.state/'patched.db.tmp-wal').exists())
 def test_catalog_search_selection_and_ambiguity(self):
  self.fixture();c=sqlite3.connect(self.base)
  c.execute('create table carrier_name(carrier_id INTEGER,name TEXT)')
  c.executemany('insert into carrier_name values(?,?)',[(7001,'Tunisie Telecom'),(8002,'Orange "Tunisia"')])
  c.executemany('insert into carrier_info values(?,?)',[(9001,'12345'),(9002,'12345')]);c.commit();c.close()
  before=self.base.read_bytes()
  p=subprocess.run([str(JDK/'bin/java.exe'),'-cp',self.cp,'com.nodecockpit.carrier.CarrierDatabaseTool','catalog',str(self.base),str(self.state),'q:'+base64.b64encode(b'orange').decode(),'60502'],capture_output=True,text=True)
  self.assertEqual(p.returncode,0,p.stderr)
  result=json.loads(base64.b64decode(p.stdout.strip().split('catalog=')[1]))
  self.assertEqual([i['mccmnc'] for i in result['items']],['60501'])
  self.assertEqual(result['items'][0]['name'],'Orange "Tunisia"')
  self.assertEqual([i['mccmnc'] for i in result['selected']],['60502'])
  self.assertEqual(before,self.base.read_bytes());self.assertFalse(self.state.exists())
 def test_corrupt_source_is_preserved(self):
  self.base.write_bytes(b'not a database');self.run_tool(False)
 def test_available_vendor_fixtures(self):
  fixtures=[ROOT/'build/carrier-stock-CP4A.db',ROOT/'build/carrier-legacy-v2-cfg.db']
  for fixture in fixtures:
   if not fixture.exists():continue
   with self.subTest(fixture=fixture.name):
    self.base.write_bytes(fixture.read_bytes());self.run_tool();c=sqlite3.connect(self.state/'patched.db');self.assertEqual(c.execute('pragma integrity_check').fetchone(),('ok',));c.close()
if __name__=='__main__':unittest.main()
