// Runs beside the download worker on the destination computer.
const remoteOtaWorker = r'''
import collections
import hashlib
import json
import os
from pathlib import Path
import re
import runpy
import shutil
import ssl
import subprocess
import sys
import threading
import time
import zipfile


runtime = runpy.run_path(str(Path(__file__).with_name('worker-1.py')))
write_json = runtime['write_json']
read_json = runtime['read_json']
lock = runtime['lock']
ROOT = Path.home() / '.wirehelm' / 'ota-preparation'
ACTIVE = {'starting', 'source', 'keys', 'extracting', 'compatibility', 'rooting', 'signing', 'verifying', 'checksum'}


def resolve(text, directory=False):
    if os.name == 'nt' and re.match(r'^/[A-Za-z]:/', text):
        text = text[1:]
    result = Path(text).expanduser().resolve(strict=True)
    if directory != result.is_dir():
        raise ValueError('Choose an existing ' + ('folder.' if directory else 'file.'))
    return result


def browse_zip_folder(request):
    home = Path.home()
    path = request.get('path', '.')
    try:
        folder = resolve(str(home) if path == '.' else path, directory=True)
    except (FileNotFoundError, NotADirectoryError, ValueError):
        if not request.get('fallbackToHome'):
            raise ValueError('This folder could not be opened. Check its path.')
        folder = home.resolve(strict=True)
    entries = []
    try:
        with os.scandir(folder) as children:
            for child in children:
                if child.is_dir():
                    entries.append(dict(name=child.name, directory=True))
                elif child.name.lower().endswith('.zip') and child.is_file():
                    entries.append(dict(name=child.name, directory=False, bytes=child.stat().st_size))
    except OSError as error:
        raise ValueError('This folder could not be read. Check its path and permissions.') from error
    return dict(path=folder.as_posix(), entries=entries)


def metadata(path):
    with zipfile.ZipFile(path) as archive:
        names = set(archive.namelist())
        required = {'payload.bin', 'payload_properties.txt', 'META-INF/com/android/metadata'}
        if not required.issubset(names):
            raise ValueError('Select a full Android A/B OTA ZIP.')
        entry = archive.getinfo('META-INF/com/android/metadata')
        if entry.file_size > 128 * 1024:
            raise ValueError('OTA metadata is too large.')
        values = dict(line.split('=', 1) for line in archive.read(entry).decode('utf-8').splitlines() if '=' in line)
    if values.get('ota-type') != 'AB' or values.get('pre-build') or values.get('pre-build-incremental'):
        raise ValueError('Incremental OTAs are unsupported. Choose the full OTA.')
    if not values.get('pre-device') or not values.get('post-build') or not values.get('post-timestamp', '').isdigit():
        raise ValueError('The OTA is missing device or build metadata.')
    return values


def short_command(args):
    options = {'creationflags': subprocess.CREATE_NO_WINDOW} if os.name == 'nt' else {}
    result = subprocess.run([str(a) for a in args], capture_output=True, text=True,
                            encoding='utf-8', errors='replace', timeout=15, **options)
    if result.returncode:
        raise ValueError('A required tool could not run. Check the setup folder.')
    return result.stdout.strip()


def inspect(request):
    setup = resolve(request['setup'], True)
    source = resolve(request['input'])
    info = metadata(source)
    device = request.get('device', '')
    if not device or device not in info['pre-device'].split('|'):
        raise ValueError('This OTA does not target this phone’s device codename.')
    if int(info['post-timestamp']) < int(request.get('timestamp', 0)):
        raise ValueError('The OTA build is older than the installed phone build.')
    avbroot = setup / ('avbroot.exe' if os.name == 'nt' else 'avbroot')
    version = request.get('kernelSuVersion', '').removeprefix('v')
    if not re.fullmatch(r'[0-9]+\.[0-9]+\.[0-9]+', version):
        raise ValueError('A supported KernelSU manager must be installed on the phone.')
    candidates = [setup / ('ksud-v' + version + ('.exe' if os.name == 'nt' else '')),
                  setup / ('ksud.exe' if os.name == 'nt' else 'ksud')]
    ksud = next((p for p in candidates if p.is_file()), None)
    required = [avbroot, setup / 'avb.key', setup / 'ota.key', setup / 'ota.crt', setup / 'avb_pkmd.bin']
    if ksud is None or any(not p.is_file() for p in required):
        raise ValueError('Setup needs avbroot, a matching ksud tool, avb.key, ota.key, ota.crt and avb_pkmd.bin.')
    avb_version = short_command([avbroot, '--version'])
    ksu_version = short_command([ksud, '--version'])
    if ksu_version != 'ksud ' + version:
        raise ValueError('The host KernelSU tool must match the phone manager version.')
    public = (setup / 'avb_pkmd.bin').read_bytes()
    embedded = setup / 'embedded-avb-pkmd.bin'
    if embedded.is_file() and public != embedded.read_bytes():
        raise ValueError('The saved AVB public key differs from the embedded reference key.')
    cert = ssl.PEM_cert_to_DER_cert((setup / 'ota.crt').read_text(encoding='utf-8'))
    embedded_cert = setup / 'embedded-ota.crt'
    if embedded_cert.is_file() and cert != ssl.PEM_cert_to_DER_cert(embedded_cert.read_text(encoding='utf-8')):
        raise ValueError('The saved OTA certificate differs from the embedded reference certificate.')
    fingerprint = hashlib.sha256(cert).hexdigest()
    encrypted = {}
    for name in ['avb', 'ota']:
        with (setup / (name + '.key')).open('rb') as key:
            encrypted[name + 'Encrypted'] = b'ENCRYPTED' in key.readline()
    return dict(device=device, build=info['post-build'], patchLevel=info.get('post-security-patch-level', ''),
                input=str(source), inputBytes=source.stat().st_size, inputMtime=source.stat().st_mtime_ns,
                setup=str(setup), avbroot=str(avbroot), ksud=str(ksud), avbrootVersion=avb_version,
                kernelSuVersion=version, avbFingerprint=hashlib.sha256(public).hexdigest(),
                otaFingerprint=fingerprint, **encrypted)


def job_path(job_id):
    if not isinstance(job_id, str) or not re.fullmatch('[a-f0-9]{32}', job_id):
        raise ValueError('Invalid OTA job identifier.')
    path = ROOT / job_id
    if not path.is_dir() or path.is_symlink():
        raise ValueError('The preparation job was not found.')
    return path


def state(path, **values):
    result = read_json(path / 'state.json') if (path / 'state.json').exists() else {}
    result.update(values)
    result['updatedAt'] = int(time.time() * 1000)
    write_json(path / 'state.json', result)
    return result


def public_job(path):
    config = read_json(path / 'config.json')
    result = read_json(path / 'state.json')
    with lock(path / 'worker.lock') as free:
        if free and result['phase'] in ACTIVE:
            result['phase'] = 'interrupted'
        elif not free and (path / 'cancel').exists():
            result['phase'] = 'stopping'
    return dict(result, id=path.name, name=config['outputName'], folder=config['outputFolder'],
                build=config['plan']['build'], createdAt=config['createdAt'])


class Cancelled(Exception):
    pass


def check_cancel(path):
    if (path / 'cancel').exists():
        raise Cancelled()


def digest(path, job):
    sha = hashlib.sha256()
    with path.open('rb') as source:
        while True:
            check_cancel(job)
            chunk = source.read(1024 * 1024)
            if not chunk:
                break
            sha.update(chunk)
    return sha.hexdigest()


def command(path, args, work, env=None):
    check_cancel(path)
    tail = collections.deque(maxlen=80)
    options = {'creationflags': subprocess.CREATE_NO_WINDOW} if os.name == 'nt' else {}
    with subprocess.Popen([str(a) for a in args], cwd=work, env=env,
                          stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                          text=True, encoding='utf-8', errors='replace', **options) as process:
        def drain():
            for line in process.stdout:
                tail.append(line.rstrip())
        reader = threading.Thread(target=drain, daemon=True)
        reader.start()
        try:
            while process.poll() is None:
                check_cancel(path)
                time.sleep(0.15)
        except BaseException:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
            raise
        finally:
            reader.join(timeout=2)
        if process.returncode:
            # Tool arguments and passphrases are deliberately excluded.
            phase = read_json(path / 'state.json')['phase']
            if phase == 'keys':
                raise ValueError('The signing key check failed. Check the selected keys and passphrases.')
            if phase == 'verifying':
                raise ValueError('The signed OTA failed verification. No output was published.')
            raise ValueError('The ' + Path(args[0]).name + ' step failed during ' + phase + '. No output was published.')
    return '\n'.join(tail)


def cleanup(work, folder, job_id):
    if work.name != '.wirehelm-ota-' + job_id or work.is_symlink() or work.parent.resolve() != folder.resolve():
        raise ValueError('Unexpected OTA working directory.')
    if work.exists():
        if any(p.is_symlink() for p in work.rglob('*')):
            raise ValueError('OTA working directory contains an unexpected symbolic link.')
        shutil.rmtree(work)


def prepare(path, config, secrets):
    plan = config['plan']
    source = Path(plan['input'])
    setup = Path(plan['setup'])
    folder = Path(config['outputFolder'])
    output = folder / config['outputName']
    work = folder / ('.wirehelm-ota-' + path.name)
    work.mkdir(mode=0o700)
    try:
        state(path, phase='source')
        if digest(source, path) != config['sha256']:
            raise ValueError('The source OTA SHA-256 does not match the supplied checksum.')
        if source.stat().st_size != plan['inputBytes'] or source.stat().st_mtime_ns != plan['inputMtime']:
            raise ValueError('The source OTA changed after inspection.')
        avb = plan['avbroot']
        ksu = plan['ksud']
        trusted_avb = (setup / 'avb_pkmd.bin').read_bytes()
        trusted_cert = (setup / 'ota.crt').read_bytes()
        if hashlib.sha256(trusted_avb).hexdigest() != plan['avbFingerprint']:
            raise ValueError('The trusted AVB public key changed after inspection.')
        if hashlib.sha256(ssl.PEM_cert_to_DER_cert(trusted_cert.decode('utf-8'))).hexdigest() != plan['otaFingerprint']:
            raise ValueError('The OTA certificate changed after inspection.')
        pinned_avb = work / 'trusted-avb.bin'
        pinned_cert = work / 'trusted-ota.crt'
        pinned_avb.write_bytes(trusted_avb)
        pinned_cert.write_bytes(trusted_cert)
        # Keep host-tool execution serial after inconsistent parallel verification.
        environment = dict(os.environ, TMP=str(work), TEMP=str(work), TMPDIR=str(work), RAYON_NUM_THREADS='1')
        signing_env = dict(environment, WIREHELM_AVB_PASS=secrets.get('avb', ''), WIREHELM_OTA_PASS=secrets.get('ota', ''))
        state(path, phase='keys')
        avb_public = work / 'avb-public.bin'
        ota_public = work / 'ota-public.bin'
        cert_public = work / 'cert-public.bin'
        command(path, [avb, 'key', 'encode-avb', '--key', setup / 'avb.key', '--pass-env-var', 'WIREHELM_AVB_PASS', '--output', avb_public], work, signing_env)
        if avb_public.read_bytes() != trusted_avb:
            raise ValueError('The AVB private key does not match the trusted public key.')
        command(path, [avb, 'key', 'encode-avb', '--key', setup / 'ota.key', '--pass-env-var', 'WIREHELM_OTA_PASS', '--output', ota_public], work, signing_env)
        command(path, [avb, 'key', 'encode-avb', '--cert', pinned_cert, '--output', cert_public], work, environment)
        if ota_public.read_bytes() != cert_public.read_bytes():
            raise ValueError('The OTA private key does not match its certificate.')
        command(path, [avb, 'ota', 'verify', '--input', source], work, environment)
        state(path, phase='extracting')
        images = work / 'images'
        images.mkdir()
        command(path, [avb, 'ota', 'extract', '--input', source, '--directory', images,
                       '--partition', 'boot', '--partition', 'init_boot'], work, environment)
        state(path, phase='compatibility')
        # KernelSU reads the target kernel's compression and KMI itself. The
        # scratch boot patch is used only to obtain that compatibility result.
        probe = command(path, [ksu, 'boot-patch', '--boot', images / 'boot.img',
                               '--out', work, '--out-name', 'kmi-probe.img'], work, environment)
        match = re.search(r'^- KMI: (android[0-9]+-[0-9]+\.[0-9]+)$', probe, re.M)
        if not match:
            raise ValueError('KernelSU could not identify the target OTA kernel compatibility.')
        kmi = match[1]
        (work / 'kmi-probe.img').unlink()
        state(path, phase='rooting', kmi=kmi)
        patched = work / 'kernelsu-init-boot.img'
        command(path, [ksu, 'boot-patch', '--boot', images / 'init_boot.img', '--kmi', kmi,
                       '--out', work, '--out-name', patched.name], work, environment)
        state(path, phase='signing')
        signed = work / 'signed-ota.zip'
        command(path, [avb, 'ota', 'patch', '--input', source, '--output', signed,
                       '--key-avb', setup / 'avb.key', '--key-ota', setup / 'ota.key',
                       '--cert-ota', pinned_cert, '--pass-avb-env-var', 'WIREHELM_AVB_PASS',
                       '--pass-ota-env-var', 'WIREHELM_OTA_PASS', '--prepatched', patched], work, signing_env)
        secrets.clear()
        signing_env.clear()
        state(path, phase='verifying')
        command(path, [avb, 'ota', 'verify', '--input', signed, '--cert-ota', pinned_cert,
                       '--public-key-avb', pinned_avb], work, environment)
        signed_info = metadata(signed)
        if signed_info['post-build'] != plan['build'] or plan['device'] not in signed_info['pre-device'].split('|'):
            raise ValueError('The signed OTA metadata does not match the selected source.')
        if source.stat().st_size != plan['inputBytes'] or source.stat().st_mtime_ns != plan['inputMtime']:
            raise ValueError('The source OTA changed during preparation.')
        state(path, phase='checksum')
        checksum = digest(signed, path)
        check_cancel(path)
        os.link(signed, output)
        public_result = dict(sha256=checksum, bytes=output.stat().st_size, kmi=kmi)
        state(path, phase='complete', error='', **public_result)
    finally:
        secrets.clear()
        cleanup(work, folder, path.name)


def worker(path, secrets):
    with lock(path / 'worker.lock') as held:
        if not held:
            secrets.clear()
            return
        config = read_json(path / 'config.json')
        try:
            prepare(path, config, secrets)
        except Cancelled:
            state(path, phase='cancelled', error='')
        except Exception as error:
            # Only messages created here are returned. Child tool output is
            # kept in memory and never copied into the job journal.
            message = str(error) if isinstance(error, ValueError) else 'Preparation failed during ' + read_json(path / 'state.json')['phase'] + '.'
            if read_json(path / 'state.json').get('phase') == 'complete':
                state(path, warning='The verified output is ready. Temporary files could not all be removed.')
            else:
                state(path, phase='failed', error=message[:400])
        finally:
            secrets.clear()


def start(request):
    job_id = request['id']
    if not isinstance(job_id, str) or not re.fullmatch('[a-f0-9]{32}', job_id):
        raise ValueError('Invalid OTA job identifier.')
    existing = ROOT / job_id
    if existing.exists():
        return public_job(job_path(job_id))
    plan = inspect(request)
    sha = request.get('sha256', '').strip().lower()
    if not re.fullmatch('[a-f0-9]{64}', sha):
        raise ValueError('Supply the full source OTA SHA-256 from its download page.')
    folder = resolve(request['outputFolder'], True)
    name = request['outputName'].strip()
    if not name.lower().endswith('.zip') or len(name.encode('utf-8')) > 180 or re.search(r'[<>:"/\\|?*\x00-\x1f]', name):
        raise ValueError('Choose a ZIP filename without path separators or reserved characters.')
    if name.split('.')[0].upper() in {'CON', 'PRN', 'AUX', 'NUL', *['COM%d' % n for n in range(1, 10)], *['LPT%d' % n for n in range(1, 10)]}:
        raise ValueError('This output filename is reserved by Windows.')
    if (folder / name).exists() or folder / name == Path(plan['input']):
        raise ValueError('Choose a new output filename. Existing files cannot be overwritten.')
    if shutil.disk_usage(folder).free < plan['inputBytes'] * 3 + 1024 * 1024 * 1024:
        raise ValueError('Free at least three times the OTA size plus 1 GB on the output drive.')
    probe = folder / ('.wirehelm-ota-' + job_id + '.check')
    link = folder / ('.wirehelm-ota-' + job_id + '.link')
    try:
        with probe.open('xb'):
            pass
        os.link(probe, link)
    except OSError:
        raise ValueError('Choose a local output folder that supports hard links, such as NTFS or ext4.')
    finally:
        probe.unlink(missing_ok=True)
        link.unlink(missing_ok=True)
    path = ROOT / job_id
    path.mkdir(mode=0o700)
    config = dict(plan=plan, sha256=sha, outputFolder=str(folder), outputName=name,
                  createdAt=int(time.time() * 1000))
    write_json(path / 'config.json', config)
    state(path, phase='starting', error='')
    options = dict(stdin=subprocess.PIPE, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                   text=True, encoding='utf-8', close_fds=True)
    if os.name == 'nt':
        options['creationflags'] = subprocess.CREATE_NO_WINDOW | subprocess.CREATE_NEW_PROCESS_GROUP | subprocess.CREATE_BREAKAWAY_FROM_JOB
    else:
        options['start_new_session'] = True
    try:
        child = subprocess.Popen([sys.executable, str(Path(__file__).resolve()), '--worker', job_id], **options)
        json.dump({'avb': request.get('avbPassphrase', ''), 'ota': request.get('otaPassphrase', '')}, child.stdin)
        child.stdin.close()
        for _ in range(40):
            time.sleep(0.05)
            with lock(path / 'worker.lock') as free:
                if not free:
                    return public_job(path)
            if child.poll() is not None:
                return public_job(path)
        raise ValueError('The preparation worker did not acknowledge startup. Refresh its status.')
    except Exception:
        with lock(path / 'worker.lock') as free:
            if free:
                state(path, phase='failed', error='Could not start preparation. Refresh and retry.')
        raise


def main(request):
    action = request['action']
    if action == 'browse':
        return browse_zip_folder(request)
    ROOT.mkdir(mode=0o700, parents=True, exist_ok=True)
    if ROOT.is_symlink():
        raise ValueError('The preparation journal must not be a symbolic link.')
    if action == 'inspect':
        return inspect(request)
    if action == 'start':
        return start(request)
    if action == 'list':
        jobs = []
        for path in ROOT.iterdir():
            if path.is_dir() and not path.is_symlink() and re.fullmatch('[a-f0-9]{32}', path.name):
                try:
                    jobs.append(public_job(path))
                except (OSError, ValueError):
                    pass
        return dict(jobs=sorted(jobs, key=lambda j: j['createdAt'], reverse=True))
    if action == 'cancel':
        path = job_path(request['id'])
        (path / 'cancel').touch()
        with lock(path / 'worker.lock') as free:
            if free and read_json(path / 'state.json')['phase'] in ACTIVE:
                state(path, phase='cancelled', error='')
        return public_job(path)
    raise ValueError('Unknown OTA preparation action.')


if __name__ == '__main__':
    if len(sys.argv) == 3 and sys.argv[1] == '--worker':
        worker(job_path(sys.argv[2]), json.load(sys.stdin))
    else:
        try:
            import base64
            request = json.loads(base64.b64decode(sys.argv[1]).decode('utf-8'))
            result = main(request)
            request.pop('avbPassphrase', None)
            request.pop('otaPassphrase', None)
            print('__WIREHELM_DOWNLOAD__' + json.dumps(dict(ok=True, result=result)))
        except Exception as error:
            message = str(error) if isinstance(error, ValueError) else 'Could not inspect or start OTA preparation. Check the selected paths and tools.'
            print('__WIREHELM_DOWNLOAD__' + json.dumps(dict(ok=False, error=message[:400])))
''';
