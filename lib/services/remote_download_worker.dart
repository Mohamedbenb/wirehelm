// Python uses only its standard library. The SSH command installs this worker
// under the remote account and detaches each transfer from the SSH session.
const remoteDownloadWorker = r'''
import base64
import contextlib
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request


ROOT = Path.home() / '.wirehelm' / 'remote-downloads'
ACTIVE = {'starting', 'downloading', 'verifying', 'publishing'}


def write_json(path, value):
    temp = path.with_name(path.name + '.' + os.urandom(8).hex() + '.tmp')
    try:
        with temp.open('x', encoding='utf-8') as output:
            json.dump(value, output, ensure_ascii=True)
            output.flush()
            os.fsync(output.fileno())
        for attempt in range(50):
            try:
                os.replace(temp, path)
                break
            except PermissionError:
                if attempt == 49:
                    raise
                time.sleep(0.01)
    finally:
        temp.unlink(missing_ok=True)


def read_json(path):
    return json.loads(path.read_text(encoding='utf-8'))


@contextlib.contextmanager
def lock(path):
    stream = path.open('a+b')
    held = False
    try:
        if os.name == 'nt':
            import msvcrt
            stream.seek(0, os.SEEK_END)
            if stream.tell() == 0:
                stream.write(b'0')
                stream.flush()
            stream.seek(0)
            try:
                msvcrt.locking(stream.fileno(), msvcrt.LK_NBLCK, 1)
                held = True
            except OSError:
                pass
        else:
            import fcntl
            try:
                fcntl.flock(stream.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
                held = True
            except BlockingIOError:
                pass
        yield held
    finally:
        if held and os.name == 'nt':
            stream.seek(0)
            msvcrt.locking(stream.fileno(), msvcrt.LK_UNLCK, 1)
        stream.close()


def job_path(job_id):
    if not isinstance(job_id, str) or not re.fullmatch('[a-f0-9]{32}', job_id):
        raise ValueError('Invalid download identifier.')
    path = ROOT / job_id
    if not path.is_dir() or path.is_symlink():
        raise ValueError('Download was not found on this device.')
    return path


def state(path, **values):
    data = read_json(path / 'state.json') if (path / 'state.json').exists() else {}
    data.update(values)
    data['updatedAt'] = int(time.time() * 1000)
    write_json(path / 'state.json', data)
    return data


def control(path):
    file = path / 'control.json'
    return read_json(file).get('action', '') if file.exists() else ''


def public_job(path):
    config = read_json(path / 'config.json')
    data = read_json(path / 'state.json')
    with lock(path / 'worker.lock') as available:
        if data.get('phase') in ACTIVE and available:
            data['phase'] = 'interrupted'
        elif not available and control(path) in {'pause', 'cancel'}:
            data['phase'] = 'stopping'
    part = Path(config['part'])
    if part.exists() and data.get('phase') not in {'complete', 'cancelled'}:
        data['bytes'] = part.stat().st_size
    return dict(data, id=path.name, name=config['name'], folder=config['folder'],
                expectedSha256=config['sha256'], createdAt=config['createdAt'])


def release_reservation(config):
    reserve = Path(config['reservation'])
    if reserve.exists() and reserve.read_text(encoding='utf-8') == config['id']:
        reserve.unlink()


def cancel(path, config):
    Path(config['part']).unlink(missing_ok=True)
    release_reservation(config)
    state(path, phase='cancelled', error='', bytes=0)


class StopTransfer(Exception):
    pass


def check_control(path):
    if control(path) in {'pause', 'cancel'}:
        raise StopTransfer()


class HttpRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        parsed = urllib.parse.urlsplit(newurl)
        if parsed.scheme not in {'http', 'https'} or parsed.username or parsed.password:
            raise ValueError('The server redirected to an unsupported URL.')
        if urllib.parse.urlsplit(req.full_url).scheme == 'https' and parsed.scheme != 'https':
            raise ValueError('The server redirected from HTTPS to an insecure connection.')
        return super().redirect_request(req, fp, code, msg, headers, newurl)


def transfer(path, config):
    part = Path(config['part'])
    target = Path(config['folder']) / config['name']
    previous = read_json(path / 'state.json')
    # A crash after publishing must never replace a file with the same name.
    if target.exists():
        if part.exists() and os.path.samefile(part, target):
            state(path, phase='complete', bytes=target.stat().st_size, error='')
            part.unlink()
            release_reservation(config)
            return
        raise ValueError('A file with this name already exists in the destination.')
    if previous.get('errorCode') == 'checksum':
        part.unlink(missing_ok=True)
        previous = {}
    offset = part.stat().st_size if part.exists() else 0
    validator = previous.get('validator', '')
    headers = {'User-Agent': 'Wirehelm/1', 'Accept-Encoding': 'identity'}
    # Without a validator, restart to avoid joining different remote versions.
    if offset and validator:
        headers.update({'Range': 'bytes=%d-' % offset, 'If-Range': validator})
    check_control(path)
    state(path, phase='downloading', error='', errorCode='', bytes=offset)
    request = urllib.request.Request(config['url'], headers=headers)
    opener = urllib.request.build_opener(HttpRedirect())
    try:
        response = opener.open(request, timeout=20)
    except urllib.error.HTTPError as error:
        # A full partial file can remain after interruption before verification.
        expected_range = 'bytes */%d' % offset
        identity = error.headers.get('ETag') or error.headers.get('Last-Modified', '')
        if error.code == 416 and offset and validator and identity == validator and error.headers.get('Content-Range') == expected_range:
            error.close()
            finish(path, config, offset)
            return
        raise
    with response:
        identity = response.headers.get('ETag', '')
        if identity.startswith('W/'):
            identity = ''
        identity = identity or response.headers.get('Last-Modified', '')
        if response.status == 206:
            match = re.fullmatch(r'bytes ([0-9]+)-([0-9]+)/([0-9]+)', response.headers.get('Content-Range', ''))
            if not match or not offset or not validator or identity != validator or int(match[1]) != offset:
                raise ValueError('The server returned an inconsistent resume response.')
            total = int(match[3])
            if int(match[2]) != total - 1 or total <= offset:
                raise ValueError('The server returned an incomplete byte range.')
            mode = 'ab'
        elif response.status == 200:
            offset = 0
            length = response.headers.get('Content-Length')
            total = int(length) if length else None
            mode = 'wb'
        else:
            raise ValueError('The server did not return a downloadable file.')
        state(path, phase='downloading', validator=identity, total=total, bytes=offset)
        last = time.monotonic()
        with part.open(mode) as output:
            while True:
                check_control(path)
                chunk = response.read(256 * 1024)
                if not chunk:
                    break
                output.write(chunk)
                offset += len(chunk)
                if total is not None and offset > total:
                    raise ValueError('The server sent more bytes than expected.')
                if time.monotonic() - last >= 1:
                    output.flush()
                    state(path, bytes=offset)
                    last = time.monotonic()
            output.flush()
            os.fsync(output.fileno())
        if total is not None and total != offset:
            raise ValueError('The connection ended before the complete file arrived. Resume to retry.')
    finish(path, config, offset)


def finish(path, config, size):
    check_control(path)
    part = Path(config['part'])
    digest = ''
    if config['sha256']:
        state(path, phase='verifying', bytes=size)
        sha = hashlib.sha256()
        with part.open('rb') as source:
            while True:
                check_control(path)
                chunk = source.read(1024 * 1024)
                if not chunk:
                    break
                sha.update(chunk)
        digest = sha.hexdigest()
        if digest != config['sha256']:
            state(path, errorCode='checksum')
            raise ValueError('SHA-256 did not match. Retry will download the file again.')
    check_control(path)
    state(path, phase='publishing', bytes=size, actualSha256=digest)
    # Hard linking is atomic and refuses an existing destination on both hosts.
    os.link(part, Path(config['folder']) / config['name'])
    state(path, phase='complete', bytes=size, total=size, error='')
    part.unlink()
    release_reservation(config)


def worker(path):
    with lock(path / 'worker.lock') as held:
        if not held:
            return
        config = read_json(path / 'config.json')
        try:
            transfer(path, config)
        except StopTransfer:
            if control(path) == 'cancel':
                cancel(path, config)
            else:
                state(path, phase='paused', error='')
        except Exception as error:
            message = str(error)
            if isinstance(error, urllib.error.HTTPError):
                message = 'The server returned HTTP %d.' % error.code
            # Avoid persisting signed URLs in diagnostic text.
            message = message.replace(config['url'], '[download URL]')[:500]
            state(path, phase='failed', error=message)


def spawn(path):
    with lock(path / 'worker.lock') as free:
        if not free:
            return
        if read_json(path / 'state.json').get('phase') in {'complete', 'cancelled'}:
            return
    write_json(path / 'control.json', {'action': ''})
    options = dict(stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                   stderr=subprocess.DEVNULL, close_fds=True)
    if os.name == 'nt':
        options['creationflags'] = (subprocess.CREATE_NO_WINDOW |
                                   subprocess.CREATE_NEW_PROCESS_GROUP |
                                   subprocess.CREATE_BREAKAWAY_FROM_JOB)
    else:
        options['start_new_session'] = True
    state(path, phase='starting', error='')
    try:
        process = subprocess.Popen([sys.executable, str(Path(__file__).resolve()),
                                    '--worker', path.name], **options)
        for _ in range(30):
            time.sleep(0.05)
            with lock(path / 'worker.lock') as free:
                if not free:
                    return
            if read_json(path / 'state.json').get('phase') != 'starting':
                return
            if process.poll() is not None:
                raise RuntimeError('The background worker could not start.')
        raise RuntimeError('The background worker did not acknowledge startup. Refresh its status.')
    except Exception as error:
        # A live worker owns its state, even if the acknowledgement timed out.
        with lock(path / 'worker.lock') as free:
            if free:
                state(path, phase='failed', error='Could not start a detached download. ' + str(error)[:200])
        raise


def create(request):
    job_id = request['id']
    if not isinstance(job_id, str) or not re.fullmatch('[a-f0-9]{32}', job_id):
        raise ValueError('Invalid download identifier.')
    path = ROOT / job_id
    if path.exists():
        return public_job(job_path(job_id))
    url = request['url'].strip()
    parsed = urllib.parse.urlsplit(url)
    if parsed.scheme not in {'http', 'https'} or not parsed.hostname or parsed.username or parsed.password or any(ord(c) < 32 for c in url):
        raise ValueError('Enter a public HTTP or HTTPS download URL.')
    name = request['name'].strip()
    if not name or len(name) > 180 or name.endswith(('.', ' ')) or re.search(r'[<>:"/\\|?*\x00-\x1f]', name) or name in {'.', '..'}:
        raise ValueError('Choose a filename without folder separators or reserved characters.')
    if name.split('.')[0].upper() in {'CON', 'PRN', 'AUX', 'NUL', *['COM%d' % n for n in range(1, 10)], *['LPT%d' % n for n in range(1, 10)]}:
        raise ValueError('This filename is reserved by Windows.')
    sha = request.get('sha256', '').strip().lower()
    if sha and not re.fullmatch('[a-f0-9]{64}', sha):
        raise ValueError('SHA-256 must contain 64 hexadecimal characters.')
    folder_text = request['folder'].strip()
    if os.name == 'nt' and re.match(r'^/[A-Za-z]:/', folder_text):
        folder_text = folder_text[1:]
    folder = Path(folder_text).expanduser().resolve(strict=True)
    if not folder.is_dir():
        raise ValueError('Choose an existing destination folder.')
    if (folder / name).exists():
        raise ValueError('A file with this name already exists in the destination.')
    reservation = folder / ('.' + name + '.wirehelm-reservation')
    config = dict(id=job_id, url=url, name=name, folder=str(folder), sha256=sha,
                  part=str(folder / ('.' + name + '.' + job_id + '.part')),
                  reservation=str(reservation), createdAt=int(time.time() * 1000))
    # Reserve the destination before creating a journal or starting the worker.
    with reservation.open('x', encoding='utf-8') as reserve:
        reserve.write(job_id)
    try:
        probe = folder / ('.wirehelm-' + job_id + '.check')
        try:
            os.link(reservation, probe)
        except OSError:
            raise ValueError('Choose a local folder that supports hard links, such as NTFS or ext4.')
        finally:
            probe.unlink(missing_ok=True)
        path.mkdir(mode=0o700)
        write_json(path / 'config.json', config)
        state(path, phase='paused', bytes=0, total=None, error='')
    except Exception:
        release_reservation(config)
        raise
    with lock(path / 'command.lock') as held:
        if not held:
            raise ValueError('Another operation is changing this download. Refresh and retry.')
        spawn(path)
    return public_job(path)


def main(request):
    ROOT.mkdir(mode=0o700, parents=True, exist_ok=True)
    if ROOT.is_symlink():
        raise ValueError('The download journal directory must not be a symbolic link.')
    action = request['action']
    if action == 'list':
        jobs = []
        for path in ROOT.iterdir():
            if re.fullmatch('[a-f0-9]{32}', path.name) and path.is_dir() and not path.is_symlink():
                try:
                    jobs.append(public_job(path))
                except (OSError, ValueError):
                    pass
        folder = Path.home() / 'Downloads'
        return dict(folder=str(folder if folder.is_dir() else Path.home()),
                    jobs=sorted(jobs, key=lambda j: j['createdAt'], reverse=True))
    if action == 'start':
        return create(request)
    if action not in {'pause', 'resume', 'cancel'}:
        raise ValueError('Unknown download action.')
    path = job_path(request['id'])
    with lock(path / 'command.lock') as held:
        if not held:
            raise ValueError('Another operation is changing this download. Refresh and retry.')
        data = read_json(path / 'state.json')
        if data['phase'] in {'complete', 'cancelled'}:
            return public_job(path)
        if action == 'resume':
            spawn(path)
        else:
            write_json(path / 'control.json', {'action': action})
            with lock(path / 'worker.lock') as free:
                if free and read_json(path / 'state.json').get('phase') not in {'complete', 'cancelled'}:
                    if action == 'cancel':
                        cancel(path, read_json(path / 'config.json'))
                    else:
                        state(path, phase='paused', error='')
    return public_job(path)


if __name__ == '__main__':
    if len(sys.argv) == 3 and sys.argv[1] == '--worker':
        worker(job_path(sys.argv[2]))
    else:
        try:
            request = json.loads(base64.b64decode(sys.argv[1]).decode('utf-8'))
            print('__WIREHELM_DOWNLOAD__' + json.dumps(dict(ok=True, result=main(request))))
        except Exception as error:
            print('__WIREHELM_DOWNLOAD__' + json.dumps(dict(ok=False, error=str(error)[:500])))
''';
