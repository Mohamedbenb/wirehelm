"""Create a deterministic KernelSU ZIP and its APK-bundled integrity record."""
from pathlib import Path
from zipfile import ZipFile, ZipInfo, ZIP_DEFLATED
import hashlib
import sqlite3

root = Path(__file__).resolve().parent.parent
target = root / 'android/customization/src/main/assets'
target.mkdir(parents=True, exist_ok=True)


def package_module(name: str) -> None:
    source = root / 'modules' / name
    archive = target / f'{name}.zip'
    with ZipFile(archive, 'w', compression=ZIP_DEFLATED) as output:
        for path in sorted(source.iterdir()):
            if path.is_file():
                entry = ZipInfo(path.name, (2026, 1, 1, 0, 0, 0))
                entry.external_attr = (
                    0o100755 if path.suffix == '.sh' else 0o100644
                ) << 16
                data = path.read_bytes()
                if path.suffix in {'.sh', '.prop'}:
                    data = data.replace(b'\r\n', b'\n')
                output.writestr(entry, data, compress_type=ZIP_DEFLATED)
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    (target / f'{name}.sha256').write_text(digest, encoding='ascii')
    print(f'Packaged {name}: {digest}')


carrier_db = root / 'modules/node-cockpit-carrier/cfg.db'
if not carrier_db.is_file():
    if any((target / f'node-cockpit-carrier.{suffix}').exists() for suffix in ('zip', 'sha256')):
        raise SystemExit('Carrier database missing while generated carrier assets are present.')
    package_module('node-cockpit-system')
    print('Skipped optional carrier backend: no local carrier database.')
    raise SystemExit(0)

expected_db_hash = '17faf3c27a4f8939f712eb280118e2b15fdef3ea7564ac921535cfcb1c1c3a6e'
if hashlib.sha256(carrier_db.read_bytes()).hexdigest() != expected_db_hash:
    raise SystemExit('Carrier cfg.db differs from the known-good artifact')
with sqlite3.connect(f'file:{carrier_db.as_posix()}?mode=ro', uri=True) as db:
    if db.execute('PRAGMA integrity_check').fetchone()[0] != 'ok':
        raise SystemExit('Carrier cfg.db failed SQLite integrity check')
    mappings = dict(
        db.execute(
            "SELECT carrier_id, confman FROM confmap WHERE carrier_id IN ('1731','1936')"
        )
    )
if mappings != {
    '1731': '185a2d82ac1e10bf3911e46a882e993cf72621ab',
    '1936': '185a2d82ac1e10bf3911e46a882e993cf72621ab',
}:
    raise SystemExit('Carrier cfg.db does not contain the approved Tunisia mappings')

package_module('node-cockpit-system')
package_module('node-cockpit-carrier')
