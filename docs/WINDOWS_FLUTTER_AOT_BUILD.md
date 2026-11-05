# Windows Flutter AOT build workaround

Use this workaround if the normal Flutter release build fails during JIT startup on Windows. A prior release reached the APK packaging step with an invalid Flutter frontend because it omitted Dart plugin registration and the Android target. The script below includes both.

## Tools and scope

SDK: C:/flutter. Working tools: bin/cache/dart-sdk/bin/dartaotruntime.exe and snapshots/frontend_server_aot.dart.snapshot. Host gen_snapshot: bin/cache/artifacts/engine/android-arm64-release/windows-x64/gen_snapshot.exe. JBR25 R8 C2 also crashes intermittently; use TieredStopAtLevel1/ActiveProcessorCount2 for Gradle.

The isolated Flutter launcher was compiled without changing SDK source:

```powershell
C:\flutter\bin\cache\dart-sdk\bin\dartaotruntime.exe C:\flutter\bin\cache\dart-sdk\bin\snapshots\dartdev_aot.dart.snapshot compile aot-snapshot --packages=C:\flutter\packages\flutter_tools\.dart_tool\package_config.json --output=C:\remote_control\build\flutter-tools-cleanup.aot C:\flutter\packages\flutter_tools\bin\flutter_tools.dart
$env:FLUTTER_ROOT='C:\flutter'
```

Use dartaotruntime with that launcher if normal analysis fails. Widget tests that mock platform channels do not establish release startup or plugin registration.

## Fresh production frontend

From C:/remote_control, use scripts/compile_android_frontend.py with --native-assets pointing to a verified Android native-assets map and --output-prefix set to a fresh build path. The script passes the Android target and generated Dart plugin registrants to KernelCompiler. The first Flutter frame depends on successful Dart initialization of SharedPreferences.

Only reuse an existing Android native-assets map when verified unchanged/empty (245 has unchanged dependencies and objective_c does nothing on Android). Native dependency changes require a proper hook/assets build; do not invent mappings or bypass it. The script records exact arguments, target, registrant and output hash, checks plugin dependencies, and explicitly records phone_startup_validated:false. This evidence is not device startup validation.

The script runs Android ARM64 gen_snapshot with --deterministic --snapshot_kind=app-aot-elf. Stage its fresh .so binary as build/app/intermediates/flutter/release/arm64-v8a/app.so. Let AGP perform Android stripping, as the stock Flutter build does. Preserve unchanged Flutter assets/fonts; verify no newly required assets/glyphs were introduced.

Run :app:assembleRelease with -x :app:compileFlutterBuildRelease -Ptarget-platform=android-arm64. This exclusion is safe only after staging the freshly compiled frontend. Verify the merged native library matches the staged binary, then verify the APK matches AGP's stripped library. AGP can change ELF bookkeeping even with gen_snapshot --strip; compare loaded code/data segments (excluding the ELF header) before declaring a hash difference stale. Also verify version, signature, Xposed entry and removed services/classes. A successful Gradle package of stale inputs is not a new UI build.

Record the resulting APK hash and any installation or startup verification in the handoff.
