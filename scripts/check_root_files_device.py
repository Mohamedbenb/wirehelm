"""Compile and run isolated root explorer checks; never operates the phone UI."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import uuid

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--serial', required=True)
    parser.add_argument('--port', default='5037')
    args = parser.parse_args()
    project = Path(__file__).resolve().parent.parent
    out = project / 'build/root-files-checks'
    classes = out / 'classes'
    classes.mkdir(parents=True, exist_ok=True)
    sdk = Path(os.environ['LOCALAPPDATA']) / 'Android/sdk'
    java = Path('C:/Program Files/Android/Android Studio/jbr/bin')
    android = sdk / 'platforms/android-37.0/android.jar'
    sources = list((project / 'android/app/src/main/java/com/example/remote_control/files').glob('*.java'))
    sources += [project / 'android/app/src/test/java/com/example/remote_control/files/RootFilesDeviceChecks.java']
    def run(cmd, **kwargs):
        return subprocess.run([str(x) for x in cmd], check=True, text=True, encoding='utf-8', capture_output=True, timeout=90, **kwargs)
    run([java/'javac.exe', '-encoding', 'UTF-8', '-source', '17', '-target', '17', '-cp', android, '-d', classes, *sources])
    jar = out/'checks.jar'
    run([java/'java.exe', '-cp', sdk/'build-tools/36.0.0/lib/d8.jar', 'com.android.tools.r8.D8', '--lib', android, '--min-api', '26', '--output', jar, *classes.rglob('*.class')])
    adb = ['adb', '-P', args.port, '-s', args.serial]
    remote = '/data/local/tmp/node-cockpit-file-checks-' + uuid.uuid4().hex + '.jar'
    run([*adb, 'push', jar, remote])
    try:
        result = run([*adb, 'shell', 'su', '-c', f'CLASSPATH={remote} app_process /system/bin com.example.remote_control.files.RootFilesDeviceChecks'])
        line = next(x for x in result.stdout.splitlines() if x.startswith('{'))
        report = json.loads(line)
        (out/'results.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
        print(json.dumps(report, indent=2))
    finally:
        run([*adb, 'shell', 'rm', '-f', remote])

if __name__ == '__main__':
    main()
