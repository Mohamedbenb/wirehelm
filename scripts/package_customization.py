"""Create a deterministic KernelSU ZIP and its APK-bundled integrity record."""
from pathlib import Path
from zipfile import ZipFile, ZipInfo, ZIP_DEFLATED
import hashlib

root = Path(__file__).resolve().parent.parent
target = root / 'android/customization/src/main/assets'
target.mkdir(parents=True, exist_ok=True)


def package_module(name: str) -> None:
    source = root / 'modules' / name
    archive = target / f'{name}.zip'
    with ZipFile(archive, 'w', compression=ZIP_DEFLATED) as output:
        for path in sorted(source.iterdir()):
            if path.is_file() and not (name == "node-cockpit-carrier" and path.name not in {"common.sh", "control.sh", "post-fs-data.sh", "post-mount.sh", "customize.sh", "module.prop", "carriers.list", "patcher.jar", "patcher.sha256"}):
                entry = ZipInfo(path.name, (2026, 1, 1, 0, 0, 0))
                entry.external_attr = (
                    0o100755 if path.suffix == '.sh' else 0o100644
                ) << 16
                data = path.read_bytes()
                if path.suffix in {'.sh', '.prop', '.list'}:
                    data = data.replace(b'\r\n', b'\n')
                output.writestr(entry, data, compress_type=ZIP_DEFLATED)
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    (target / f'{name}.sha256').write_text(digest, encoding='ascii')
    print(f'Packaged {name}: {digest}')


# Carrier backend contains code only; vendor data is copied on the device.
import os
import subprocess
import shutil

sdk = Path(os.environ.get('ANDROID_SDK_ROOT') or os.environ.get('ANDROID_HOME') or
           Path.home() / ('AppData/Local/Android/sdk' if os.name == 'nt' else 'Android/Sdk'))
jdk = os.environ.get('JAVA_HOME')
if jdk:
    javac = Path(jdk) / 'bin' / ('javac.exe' if os.name == 'nt' else 'javac')
elif os.name == 'nt':
    jdk = 'C:/Program Files/Android/Android Studio/jbr'
    javac = Path(jdk) / 'bin/javac.exe'
else:
    javac = shutil.which('javac')
    if not javac:
        raise SystemExit('Set JAVA_HOME or add javac to PATH.')
work = root / 'build/carrier-patcher'
classes = work / 'classes'
dex = work / 'dex'
classes.mkdir(parents=True, exist_ok=True)
dex.mkdir(parents=True, exist_ok=True)
source = root / 'scripts/carrier/CarrierDatabaseTool.java'
platforms = sorted((sdk/'platforms').glob('android*/android.jar'), key=lambda p: tuple(int(v) for v in __import__('re').findall(r'\d+', p.parent.name)))
if not platforms:
    raise SystemExit('No Android SDK platform found for carrier patcher compilation')
android_jar = platforms[-1]
d8 = sdk / 'build-tools/36.0.0' / ('d8.bat' if os.name == 'nt' else 'd8')
env = os.environ.copy()
if jdk:
    env['JAVA_HOME'] = jdk
subprocess.run([str(javac), '-encoding', 'UTF-8', '--release', '17', '-classpath', str(android_jar), '-d', str(classes), str(source)], check=True, env=env)
compiled = sorted(classes.rglob('*.class'))
subprocess.run([str(d8), '--min-api', '26', '--lib', str(android_jar), '--output', str(dex), *map(str, compiled)], check=True, env=env)
module = root / 'modules/node-cockpit-carrier'
with ZipFile(module/'patcher.jar', 'w', compression=ZIP_DEFLATED) as jar:
    entry = ZipInfo('classes.dex', (2026, 1, 1, 0, 0, 0))
    jar.writestr(entry, (dex/'classes.dex').read_bytes(), compress_type=ZIP_DEFLATED)
(module/'patcher.sha256').write_text(hashlib.sha256((module/'patcher.jar').read_bytes()).hexdigest(), encoding='ascii')
package_module('node-cockpit-system')
package_module('node-cockpit-carrier')
