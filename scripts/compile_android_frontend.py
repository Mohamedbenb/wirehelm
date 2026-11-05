"""Fresh Android ARM64 Flutter AOT when the host JIT launcher is unusable.

This does not run native asset hooks or package an APK. Supply a verified Android
native-assets map from the same dependencies; use normal Flutter build otherwise.
Compiler arguments mirror Flutter's KernelCompiler release path, including its
generated Dart plugin registrant (required before main loads preferences).
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--flutter-root', type=Path, default=Path('C:/flutter'))
    parser.add_argument('--native-assets', type=Path, required=True)
    parser.add_argument('--output-prefix', default='build/android-release')
    args = parser.parse_args()
    project = Path(__file__).resolve().parent.parent
    sdk = args.flutter_root.resolve()
    registrant = project / '.dart_tool/flutter_build/dart_plugin_registrant.dart'
    packages = project / '.dart_tool/package_config.json'
    native_assets = args.native_assets.resolve()
    for required in (registrant, packages, native_assets):
        if not required.is_file():
            raise SystemExit(f'Missing required input: {required}')
    # The generated Android plugin registration must be present, not substituted
    # by Java registration or by mocked widget tests.
    source = registrant.read_text(encoding='utf-8')
    if 'SharedPreferencesAndroid.registerWith()' not in source:
        raise SystemExit('Regenerate the Dart plugin registrant before compiling.')
    prefix = project / args.output_prefix
    prefix.parent.mkdir(parents=True, exist_ok=True)
    dill = Path(f'{prefix}.dill')
    depfile = Path(f'{prefix}.d')
    binary = Path(f'{prefix}.so')
    registrant_uri = registrant.as_uri()
    command = [
        str(sdk / 'bin/cache/dart-sdk/bin/dartaotruntime.exe'),
        str(sdk / 'bin/cache/dart-sdk/bin/snapshots/frontend_server_aot.dart.snapshot'),
        '--sdk-root', str(sdk / 'bin/cache/artifacts/engine/common/flutter_patched_sdk_product'),
        '--target=flutter', '--no-print-incremental-dependencies',
        '-Ddart.vm.profile=false', '-Ddart.vm.product=true',
        '--delete-tostring-package-uri=dart:ui',
        '--delete-tostring-package-uri=package:flutter',
        '--aot', '--tfa', '--target-os', 'android',
        '--packages', str(packages), '--output-dill', str(dill),
        '--depfile', str(depfile),
        '--source', registrant_uri,
        '--source', 'package:flutter/src/dart_plugin_registrant.dart',
        f'-Dflutter.dart_plugin_registrant={registrant_uri}',
        '--native-assets', str(native_assets), '--verbosity=error',
        str(project / 'lib/main.dart'),
    ]
    subprocess.run(command, cwd=project, check=True)
    dependencies = depfile.read_text(encoding='utf-8').replace('\\\\', '/')
    if 'dart_plugin_registrant.dart' not in dependencies or 'shared_preferences_android' not in dependencies:
        raise SystemExit('Frontend dependency output is missing Android Dart plugin registration.')
    subprocess.run([
        str(sdk / 'bin/cache/artifacts/engine/android-arm64-release/windows-x64/gen_snapshot.exe'),
        '--deterministic', '--snapshot_kind=app-aot-elf', f'--elf={binary}',
        str(dill),
    ], cwd=project, check=True)
    payload = binary.read_bytes()
    for marker in (b'_PluginRegistrant', b'dart_plugin_registrant.dart', b'SharedPreferencesAndroid'):
        if marker not in payload:
            raise SystemExit(f'Android AOT is missing the registration marker {marker!r}')
    evidence = {
        'target_os': 'android', 'dart_plugin_registrant': registrant_uri,
        'frontend_command': command,
        'aot_sha256': hashlib.sha256(payload).hexdigest(),
        'phone_startup_validated': False,
    }
    Path(f'{prefix}.json').write_text(json.dumps(evidence, indent=2), encoding='utf-8')
    print(f'Fresh Android AOT compiled: {binary}. Phone startup remains unverified.')


if __name__ == '__main__':
    main()
