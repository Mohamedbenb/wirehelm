"""Read back a guarded explorer install and test its packaged Java entry point."""
import argparse
import json
from pathlib import Path
import shlex
import subprocess

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--build', required=True, type=int)
    parser.add_argument('--serial', required=True)
    parser.add_argument('--port', default='5037')
    parser.add_argument('--advanced-check', action='store_true')
    parser.add_argument('--customization-check', action='store_true')
    args = parser.parse_args()
    adb = ['adb', '-P', args.port, '-s', args.serial]
    def run(arguments):
        return subprocess.run([*adb, *arguments], check=True, text=True, encoding='utf-8', capture_output=True, timeout=30).stdout
    version = run(['shell', 'cmd', 'package', 'list', 'packages', '--show-versioncode', 'com.example.remote_control']).strip()
    assert version == f'package:com.example.remote_control versionCode:{args.build}', version
    log = run(['shell', 'su', '-c', f'cat /data/local/tmp/node{args.build}-root-explorer-install.log'])
    assert f'END{args.build}' in log and 'Success' in log, log
    values = dict(line.split('=', 1) for line in log.splitlines() if line.startswith('SYSTEMUI_'))
    assert values['SYSTEMUI_BEFORE'] and values['SYSTEMUI_BEFORE'] == values['SYSTEMUI_AFTER'], values
    apk = run(['shell', 'pm', 'path', 'com.example.remote_control']).strip().splitlines()[0].removeprefix('package:')
    assert apk.startswith('/data/app/') and apk.endswith('/base.apk')
    request = json.dumps({'op': 'list', 'path': '/data/local/tmp'})
    command = "printf '%s' " + shlex.quote(request) + ' | CLASSPATH=' + shlex.quote(apk) + ' /system/bin/app_process /system/bin com.example.remote_control.files.RootFileWorker'
    response = json.loads(next(line for line in run(['shell', 'su -c ' + shlex.quote(command)]).splitlines() if line.startswith('{')))
    assert 'error' not in response, response.get('error')
    assert response['path'] == '/data/local/tmp' and response['unlockable']
    if args.advanced_check or args.customization_check:
        checks = [('/data/local', True), ('/system', False), ('/proc', False)]
        if args.customization_check: checks.append(('/data/adb', True))
        for path, advanced in checks:
            request = json.dumps({'op': 'list', 'path': path})
            command = "printf '%s' " + shlex.quote(request) + ' | CLASSPATH=' + shlex.quote(apk) + ' /system/bin/app_process /system/bin com.example.remote_control.files.RootFileWorker'
            result = json.loads(next(line for line in run(['shell', 'su -c ' + shlex.quote(command)]).splitlines() if line.startswith('{')))
            assert 'error' not in result, result.get('error')
            assert result['unlockable'] is False and result['advancedUnlockable'] is advanced, path
    report = {'build': args.build, 'installed': True, 'packagedRootHelperWorks': True, 'systemUiPidBefore': int(values['SYSTEMUI_BEFORE']), 'systemUiPidAfter': int(values['SYSTEMUI_AFTER']), 'systemUiRestarted': False, 'uiValidated': False}
    report['advancedPolicyReadback'] = args.advanced_check
    report['customizationPolicyReadback'] = args.customization_check
    root = Path(__file__).resolve().parent.parent
    (root/f'build/root-files-checks/installed{args.build}.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    run(['shell', 'su', '-c', f'rm -f /data/local/tmp/node{args.build}-root-explorer.apk'])
    print(json.dumps(report))

if __name__ == '__main__':
    main()
