"""Exercise the actual bundled worker against a local HTTP range server."""
import base64
import hashlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import runpy
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import time
import unittest
import uuid


class RemoteDownloadsTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='wirehelm-download-test-')
        self.home = Path(self.temp.name)
        self.destination = self.home / 'Downloads'
        self.destination.mkdir()
        self.script = self.home / 'worker.py'
        source = Path(__file__).resolve().parents[1] / 'lib/services/remote_download_worker.dart'
        self.script.write_text(source.read_text(encoding='utf-8').split("r'''", 1)[1].rsplit("''';", 1)[0], encoding='utf-8')
        self.env = dict(os.environ, USERPROFILE=str(self.home), HOME=str(self.home))
        self.data = bytes(range(256)) * (32 * 1024)
        self.etag = '"version-1"'
        self.requests = []
        self.job_ids = []
        owner = self

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def do_GET(self):
                data = owner.data
                etag = owner.etag
                requested = self.headers.get('Range', '')
                validator = self.headers.get('If-Range', '')
                owner.requests.append((requested, validator))
                start = int(requested[6:-1]) if requested and validator == etag else 0
                if start >= len(data):
                    self.send_response(416)
                    self.send_header('Content-Range', 'bytes */%d' % len(data))
                    self.send_header('ETag', etag)
                    self.end_headers()
                    return
                self.send_response(206 if start else 200)
                self.send_header('Content-Length', str(len(data) - start))
                if etag:
                    self.send_header('ETag', etag)
                if start:
                    self.send_header('Content-Range', 'bytes %d-%d/%d' % (start, len(data) - 1, len(data)))
                self.end_headers()
                try:
                    for offset in range(start, len(data), 32 * 1024):
                        self.wfile.write(data[offset:offset + 32 * 1024])
                        self.wfile.flush()
                        time.sleep(0.003)
                except (BrokenPipeError, ConnectionResetError, ConnectionAbortedError):
                    pass

        self.server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        self.server.daemon_threads = True
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()

    def tearDown(self):
        try:
            for job_id in self.job_ids:
                self.call('cancel', id=job_id)
                self.wait(job_id, {'complete', 'cancelled'})
        finally:
            self.server.shutdown()
            self.server.server_close()
            self.thread.join()
            self.temp.cleanup()

    def call(self, action, **args):
        payload = base64.b64encode(json.dumps(dict(action=action, **args)).encode()).decode()
        run = subprocess.run([sys.executable, str(self.script), payload], env=self.env,
                             capture_output=True, text=True, timeout=30, check=True)
        return json.loads(run.stdout.strip().split('__WIREHELM_DOWNLOAD__', 1)[1])

    def start(self, sha=''):
        job_id = uuid.uuid4().hex
        self.job_ids.append(job_id)
        reply = self.call('start', id=job_id, url='http://127.0.0.1:%d/file.zip' % self.server.server_port,
                          folder=str(self.destination), name=job_id + '.zip', sha256=sha)
        self.assertTrue(reply['ok'], reply)
        return job_id

    def status(self, job_id):
        reply = self.call('list')
        self.assertTrue(reply['ok'], reply)
        return next(job for job in reply['result']['jobs'] if job['id'] == job_id)

    def wait(self, job_id, phases, min_bytes=0):
        end = time.monotonic() + 20
        while time.monotonic() < end:
            status = self.status(job_id)
            if status['phase'] in phases and status['bytes'] >= min_bytes:
                return status
            time.sleep(0.05)
        self.fail('Download did not reach %s: %s' % (phases, status))

    def pause(self, job_id):
        self.wait(job_id, {'downloading'}, min_bytes=256 * 1024)
        self.assertTrue(self.call('pause', id=job_id)['ok'])
        return self.wait(job_id, {'paused'})

    def assert_file(self, job_id, expected):
        self.assertEqual((self.destination / (job_id + '.zip')).read_bytes(), expected)

    def test_detached_completion_checksum_and_existing_file(self):
        sha = hashlib.sha256(self.data).hexdigest()
        job_id = self.start(sha)
        finished = self.wait(job_id, {'complete'})
        self.assertEqual(finished['actualSha256'], sha)
        self.assert_file(job_id, self.data)
        reply = self.call('start', id=uuid.uuid4().hex, url='http://localhost/test',
                          folder=str(self.destination), name=job_id + '.zip', sha256='')
        self.assertFalse(reply['ok'])
        self.assert_file(job_id, self.data)

    def test_stale_resume_cannot_restart_a_completed_worker(self):
        self.data = b'small complete file'
        job_id = self.start()
        self.wait(job_id, {'complete'})
        module = runpy.run_path(str(self.script))
        path = self.home / '.wirehelm' / 'remote-downloads' / job_id
        module['spawn'](path)
        self.assertEqual(self.status(job_id)['phase'], 'complete')
        self.assert_file(job_id, self.data)

    def test_pause_resume_preserves_validated_range(self):
        job_id = self.start()
        paused = self.pause(job_id)
        time.sleep(0.1)
        self.assertEqual(self.status(job_id)['bytes'], paused['bytes'])
        self.assertTrue(self.call('resume', id=job_id)['ok'])
        self.assertTrue(self.call('resume', id=job_id)['ok'])
        self.wait(job_id, {'complete'})
        self.assert_file(job_id, self.data)
        self.assertIn(('bytes=%d-' % paused['bytes'], self.etag), self.requests)
        self.assertEqual(len(self.requests), 2)

    def test_destination_created_during_download_is_never_overwritten(self):
        job_id = self.start()
        self.wait(job_id, {'downloading'}, min_bytes=256 * 1024)
        target = self.destination / (job_id + '.zip')
        target.write_bytes(b'user-created file')
        self.wait(job_id, {'failed'})
        self.assertEqual(target.read_bytes(), b'user-created file')

    def test_changed_resource_restarts_without_mixing_versions(self):
        job_id = self.start()
        self.pause(job_id)
        self.etag = '"version-2"'
        self.data = b'changed-version-' * (512 * 1024)
        self.assertTrue(self.call('resume', id=job_id)['ok'])
        self.wait(job_id, {'complete'})
        self.assert_file(job_id, self.data)

    def test_missing_validator_restarts(self):
        self.etag = ''
        job_id = self.start()
        self.pause(job_id)
        self.assertTrue(self.call('resume', id=job_id)['ok'])
        self.wait(job_id, {'complete'})
        self.assert_file(job_id, self.data)
        self.assertTrue(all(not byte_range for byte_range, _ in self.requests))

    def test_checksum_failure_is_not_published_and_retry_restarts(self):
        good = self.data
        sha = hashlib.sha256(good).hexdigest()
        self.data = b'wrong version'
        job_id = self.start(sha)
        self.wait(job_id, {'failed'})
        self.assertFalse((self.destination / (job_id + '.zip')).exists())
        self.data = good
        self.assertTrue(self.call('resume', id=job_id)['ok'])
        self.wait(job_id, {'complete'})
        self.assert_file(job_id, good)
        self.assertEqual(self.requests[-1], ('', ''))

    def test_cancel_releases_destination_and_removes_partial(self):
        job_id = self.start()
        self.wait(job_id, {'downloading'}, min_bytes=256 * 1024)
        self.assertTrue(self.call('cancel', id=job_id)['ok'])
        self.wait(job_id, {'cancelled'})
        self.assertFalse((self.destination / (job_id + '.zip')).exists())
        self.assertEqual(list(self.destination.iterdir()), [])


if __name__ == '__main__':
    unittest.main()
