"""Explicit host integration tests using throwaway keys and an existing stock OTA.

Set WIREHELM_OTA_FIXTURE to the stock ZIP. The input and real signing keys are
never modified. Outputs, generated test keys, and journals use a temporary home.
"""
import base64
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
import uuid


@unittest.skipUnless(os.environ.get('WIREHELM_OTA_FIXTURE'), 'Set WIREHELM_OTA_FIXTURE for the full host integration test')
class OtaPreparationTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix='wirehelm-ota-integration-')
        cls.home = Path(cls.temp.name)
        cls.source = Path(os.environ['WIREHELM_OTA_FIXTURE']).resolve()
        cls.setup = cls.home / 'setup'
        cls.output = cls.home / 'output'
        cls.setup.mkdir()
        cls.output.mkdir()
        cls.secret = 'throwaway-test-pass-' + uuid.uuid4().hex
        cls.env = dict(os.environ, USERPROFILE=str(cls.home), HOME=str(cls.home), RAYON_NUM_THREADS='1',
                       WIREHELM_TEST_PASSPHRASE=cls.secret)
        project = Path(__file__).resolve().parents[1]
        for name, filename in [('remote_download_worker', 'worker-1.py'), ('remote_ota_worker', 'ota-worker-1.py')]:
            text = (project / 'lib/services' / (name + '.dart')).read_text(encoding='utf-8')
            code = text.split("r'''", 1)[1].rsplit("''';", 1)[0]
            (cls.home / filename).write_text(code, encoding='utf-8')
        cls.script = cls.home / 'ota-worker-1.py'
        avbroot = Path(os.environ.get('WIREHELM_AVBROOT', 'C:/avbroot-pixel10/avbroot.exe'))
        ksud = Path(os.environ.get('WIREHELM_KSUD', 'C:/avbroot-pixel10/ksud-v3.3.1.exe'))
        cls.avb = cls.setup / ('avbroot.exe' if os.name == 'nt' else 'avbroot')
        shutil.copy2(avbroot, cls.avb)
        shutil.copy2(ksud, cls.setup / ('ksud-v3.3.1.exe' if os.name == 'nt' else 'ksud-v3.3.1'))
        for name in ['avb', 'ota']:
            cls.tool('key', 'generate-key', '--key-type', 'rsa4096', '--output', cls.setup / (name + '.key'),
                     '--pass-env-var', 'WIREHELM_TEST_PASSPHRASE')
        cls.tool('key', 'generate-cert', '--key', cls.setup / 'ota.key', '--output', cls.setup / 'ota.crt',
                 '--pass-env-var', 'WIREHELM_TEST_PASSPHRASE')
        cls.tool('key', 'encode-avb', '--key', cls.setup / 'avb.key', '--output', cls.setup / 'avb_pkmd.bin',
                 '--pass-env-var', 'WIREHELM_TEST_PASSPHRASE')
        with cls.source.open('rb') as stream:
            cls.source_sha = hashlib.file_digest(stream, 'sha256').hexdigest()

    @classmethod
    def tool(cls, *args):
        result = subprocess.run([str(cls.avb), *map(str, args)], env=cls.env,
                                capture_output=True, text=True, timeout=900)
        if result.returncode:
            raise RuntimeError(result.stderr[-1000:])

    @classmethod
    def tearDownClass(cls):
        try:
            data = cls.call('list')
            for job in data.get('result', {}).get('jobs', []):
                if job['phase'] not in {'complete', 'failed', 'cancelled', 'interrupted'}:
                    cls.call('cancel', id=job['id'])
            # A completed status is committed just before scratch cleanup.
            until = time.monotonic() + 30
            while time.monotonic() < until:
                jobs = cls.call('list').get('result', {}).get('jobs', [])
                if not any(cls.output.glob('.wirehelm-ota-*')) and not any(
                        j['phase'] in {'starting', 'source', 'keys', 'extracting', 'compatibility', 'rooting', 'signing', 'verifying', 'checksum', 'stopping'} for j in jobs):
                    break
                time.sleep(0.1)
        finally:
            cls.temp.cleanup()

    @classmethod
    def call(cls, action, **values):
        payload = base64.b64encode(json.dumps(dict(action=action, **values)).encode()).decode()
        result = subprocess.run([sys.executable, str(cls.script), payload], env=cls.env,
                                capture_output=True, text=True, timeout=30, check=True)
        return json.loads(result.stdout.strip().split('__WIREHELM_DOWNLOAD__', 1)[1])

    def values(self, **extra):
        return dict(setup=str(self.setup), input=str(self.source), device='frankel',
                    timestamp=0, kernelSuVersion='v3.3.1', **extra)

    def start(self, **extra):
        job_id = uuid.uuid4().hex
        values = self.values(id=job_id, outputFolder=str(self.output), outputName=job_id + '.zip',
                             sha256=self.source_sha, avbPassphrase=self.secret, otaPassphrase=self.secret)
        values.update(extra)
        result = self.call('start', **values)
        self.assertTrue(result['ok'], result)
        return job_id

    def wait(self, job_id, phases, timeout=900):
        end = time.monotonic() + timeout
        last = None
        while time.monotonic() < end:
            result = self.call('list')
            self.assertTrue(result['ok'], result)
            current = next(j for j in result['result']['jobs'] if j['id'] == job_id)
            if current['phase'] != last:
                print('OTA integration phase:', current['phase'], flush=True)
                last = current['phase']
            if current['phase'] in phases:
                return current
            if current['phase'] in {'failed', 'cancelled'}:
                self.fail(str(current))
            time.sleep(0.3)
        self.fail('Timed out waiting for preparation')

    def test_inspection_rejects_wrong_device_and_downgrade(self):
        wrong = self.values()
        wrong['device'] = 'another-pixel'
        self.assertFalse(self.call('inspect', **wrong)['ok'])
        wrong = self.values()
        wrong['timestamp'] = 9999999999
        self.assertFalse(self.call('inspect', **wrong)['ok'])
        valid = self.call('inspect', **self.values())
        self.assertTrue(valid['ok'], valid)
        self.assertTrue(valid['result']['avbEncrypted'])
        self.assertTrue(valid['result']['otaEncrypted'])

    def test_existing_output_and_missing_source_checksum_are_rejected(self):
        protected = self.output / 'existing.zip'
        protected.write_bytes(b'keep this file')
        result = self.call('start', **self.values(id=uuid.uuid4().hex, sha256=self.source_sha,
                           outputFolder=str(self.output), outputName=protected.name))
        self.assertFalse(result['ok'])
        self.assertEqual(protected.read_bytes(), b'keep this file')
        result = self.call('start', **self.values(id=uuid.uuid4().hex, sha256='',
                           outputFolder=str(self.output), outputName='new.zip'))
        self.assertFalse(result['ok'])

    def test_source_checksum_and_passphrase_failures_do_not_publish(self):
        job_id = self.start(sha256='0' * 64)
        result = self.wait(job_id, {'failed'})
        self.assertIn('SHA-256', result['error'])
        self.assertFalse((self.output / (job_id + '.zip')).exists())
        job_id = self.start(avbPassphrase='wrong-passphrase')
        result = self.wait(job_id, {'failed'})
        self.assertIn('passphrase', result['error'])
        self.assertFalse((self.output / (job_id + '.zip')).exists())
        self.assert_journal_has_no_credentials()

    def test_cancel_cleans_owned_work(self):
        job_id = self.start()
        self.assertTrue(self.call('cancel', id=job_id)['ok'])
        self.wait(job_id, {'cancelled'})
        self.assertFalse((self.output / (job_id + '.zip')).exists())

    def assert_journal_has_no_credentials(self):
        root = self.home / '.wirehelm' / 'ota-preparation'
        for path in root.rglob('*.json'):
            text = path.read_text(encoding='utf-8')
            self.assertNotIn(self.secret, text)
            self.assertNotIn('wrong-passphrase', text)
            self.assertNotIn('avbPassphrase', text)
            self.assertNotIn('otaPassphrase', text)
        self.assertFalse(list(root.rglob('*.key')))

    def test_z_full_root_sign_verify_pipeline_with_throwaway_keys(self):
        before = {p.name: p.read_bytes() for p in self.setup.glob('*.key')}
        job_id = self.start()
        result = self.wait(job_id, {'complete'})
        self.assertEqual(result['kmi'], 'android15-6.6')
        signed = self.output / (job_id + '.zip')
        with signed.open('rb') as stream:
            self.assertEqual(hashlib.file_digest(stream, 'sha256').hexdigest(), result['sha256'])
        self.tool('ota', 'verify', '--input', signed, '--cert-ota', self.setup / 'ota.crt',
                  '--public-key-avb', self.setup / 'avb_pkmd.bin')
        for path in self.setup.glob('*.key'):
            self.assertEqual(path.read_bytes(), before[path.name])
        self.assert_journal_has_no_credentials()
        with self.source.open('rb') as stream:
            self.assertEqual(hashlib.file_digest(stream, 'sha256').hexdigest(), self.source_sha)


if __name__ == '__main__':
    unittest.main()
