"""Guarded root-explorer update. No UI control and no SystemUI restart."""
import argparse
from pathlib import Path
import hashlib
import json
import subprocess
import shlex

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--build', required=True, type=int)
parser.add_argument('--expected', required=True, type=int)
parser.add_argument('--serial', required=True)
parser.add_argument('--port', default='5037')
args = parser.parse_args()
build = args.build

root = Path(__file__).resolve().parent.parent
meta = json.loads((root/f'build/root-files-checks/artifact{build}.json').read_text(encoding='utf-8'))
apk = Path(meta['apk'])
assert hashlib.sha256(apk.read_bytes()).hexdigest() == meta['sha256']
adb = ['adb', '-P', args.port, '-s', args.serial]
def run(args):
    return subprocess.run([*adb, *args], text=True, encoding='utf-8', capture_output=True, timeout=240, check=True)
version = run(['shell', 'cmd', 'package', 'list', 'packages', '--show-versioncode', 'com.example.remote_control']).stdout.strip()
if version != f'package:com.example.remote_control versionCode:{args.expected}':
    raise SystemExit('Install not started: unexpected version: ' + version)
remote = f'/data/local/tmp/node{build}-root-explorer.apk'
run(['push', str(apk), remote])
device_hash = run(['shell', 'su', '-c', 'sha256sum ' + remote]).stdout.split()[0]
assert device_hash == meta['sha256']
script = f'''#!/system/bin/sh
mkdir /data/local/tmp/node{build}-root-explorer-install.once || exit 90
echo BEGIN{build}
echo SYSTEMUI_BEFORE=$(pidof com.android.systemui)
actual=$(sha256sum {remote})
[ "${{actual%% *}}" = "{meta['sha256']}" ] || exit 91
cmd package list packages --show-versioncode com.example.remote_control | grep -qx 'package:com.example.remote_control versionCode:{args.expected}' || exit 92
pm install -r {remote} || exit 93
cmd package list packages --show-versioncode com.example.remote_control
echo SYSTEMUI_AFTER=$(pidof com.android.systemui)
echo END{build}
'''
local = root/f'build/root-files-checks/install{build}.sh'
local.write_text(script, encoding='utf-8', newline='\n')
run(['push', str(local), f'/data/local/tmp/node{build}-root-explorer-install.sh'])
command = f'nohup sh /data/local/tmp/node{build}-root-explorer-install.sh >/data/local/tmp/node{build}-root-explorer-install.log 2>&1 </dev/null &'
run(['shell', 'su -c ' + shlex.quote(command)])
print(f'QUEUED_BUILD{build}_ONCE; never replay this command. Installer owns no restart.')
