# Build and deployment

## Fresh Android checkout

Install Flutter with the Dart version required by pubspec.yaml, Android SDK 37 and the NDK, a Gradle-compatible JDK, Python 3, and the Go version pinned in native/tsnet/go.mod. Set your local Android and Flutter SDK paths in android/local.properties before running Gradle directly.

```powershell
flutter pub get
.\scripts\build_tsnet.ps1 -AndroidSdk <sdk-path> -JavaDirectory <jdk-path>
python scripts/package_customization.py
flutter build apk --debug
```

The generated tsnet AAR and root module ZIPs are local build outputs. A fresh checkout builds the standard recovery backend without the optional vendor carrier database. If you have the supported database locally, the packager checks its hash and SQLite integrity before including it.

Wirehelm retains the Android application ID and updater compatibility of Node Cockpit. Updating an installed copy still requires the original signing certificate.

If the Flutter JIT launcher crashes on Windows, use the [AOT build workaround](WINDOWS_FLUTTER_AOT_BUILD.md). After Flutter changes, build a fresh app library with the Android target and Dart plugin registration.

See [code map](CODE_MAP.md) for ownership and [current handoff](CODEX_HANDOFF.md) for the latest tested build. Version numbers below are examples; choose the next build code above the installed app. Keep the package and signing key unchanged.

## Standard update build

From the project root:

```powershell
.\scripts\build_update.ps1 -BuildNumber <next-code>
```

The script packages customization backend assets, builds an ARM64 release, verifies Xposed metadata, and publishes the downloader alias plus version sidecars. Inspect the script before changing assumptions about supported architectures or output files. Historical REMOTE_UPDATES.md examples use old version numbers.

## Known working direct Gradle build on this PC

Use this when only Flutter/Java/Kotlin changed and existing backend assets/native libraries are current:

```powershell
$env:JAVA_HOME='C:\Program Files\Android\Android Studio\jbr'
$env:Path="$env:JAVA_HOME\bin;$env:Path"
Push-Location android
try {
  .\gradlew.bat --no-daemon --max-workers=1 --console plain `
    '-Dorg.gradle.jvmargs=-Xmx2g -XX:MaxMetaspaceSize=1g -XX:TieredStopAtLevel=1 -Dfile.encoding=UTF-8' `
    -q :app:assembleRelease
} finally { Pop-Location }
```

Update pubspec.yaml and android/local.properties versionName/versionCode together. Do not edit production sources while a build is running. Root backend asset changes require scripts/package_customization.py first. A direct Gradle build does not publish the update alias automatically.

Artifacts:

- build/app/outputs/apk/release/app-release.apk
- build/app/outputs/flutter-apk/node-cockpit-update.apk (the in-app downloader's normal path)
- Node-Cockpit-<version>-build<code>.apk (reviewable named release)

Copy the verified final APK to the named release and downloader alias. If using the updater's lightweight availability check, publish its matching .apk.json sidecar as scripts/build_update.ps1 does. Avoid publishing an incomplete build.

```powershell
python scripts/verify_customization_apk.py build/app/outputs/apk/release/app-release.apk
```

Inspect the actual APK version with Android SDK aapt and compare hashes when copying/transferring. Never bypass the updater's downgrade or certificate checks to mask a stale artifact.

## Native Tailscale changes

Use scripts/build_tsnet.ps1 after editing native/tsnet/bridge. Inspect native/tsnet/README.md for pinned tool/runtime requirements. The Android AAR is android/app/libs/tsnet.aar; generated source bindings must expose any new Go API before Kotlin callers can build. Cached tools live under .tools/ in this workspace. Go-only changes still need a new APK after replacing the AAR. Flutter-only/native-customization-only changes do not require rebuilding Go.

## Narrow checks when authorized

```powershell
flutter analyze --no-pub lib/screens/local_customization_screen.dart lib/customization/network_indicator_preview.dart
flutter test --no-pub test/network_indicator_preview_test.dart
```

Native tests: from android/, run :customization:testDebugUnitTest with --tests naming the relevant class. Apply the JAVA_HOME/JVM limits above. Do not claim phone graphics are validated by a successful unit test.

Use --no-pub for focused Flutter checks when dependencies are already resolved. If a release fails on a generated dev-only integration_test registrant, inspect the generated file and dependency state; do not remove production plugins or silently change the dependency graph.

## Phone deployment

```powershell
adb devices -l
adb mdns services
adb -s <connected-serial> install -r <absolute-final-apk>
adb -s <connected-serial> shell dumpsys package com.example.remote_control
```

App-only code updates do not require a SystemUI restart. Injected renderer code changes require a HOOK_VERSION bump and one controlled reload; verify the loaded version after restart. A reload can require the user to unlock normally. Do not uninstall/clear data to update: that destroys settings and the embedded tailnet identity.

Regular wireless ADB and app-hosted remote ADB have different lifetimes. An app update can terminate its own temporary remote relay; regular wireless ADB avoids that dependency. For remote-only deployment, follow REMOTE_ADB.md and read the latest handoff rather than inventing listener ports or weakening authorization/firewall protection.

## What each success proves

Build success proves compilation/packaging, not installed state. APK verification checks the artifact; adb install success plus package inspection establishes installation. A loaded HOOK_VERSION/PID check establishes injected code activation; matching settings revisions establish reported synchronization. Actual graphics/input require a scoped phone reproduction. Keep these checkpoints separate when reporting results. See [behavior guide section9](BEHAVIOR_GUIDE.md#9-update-and-deployment-success-boundaries). Documentation-only updates require no APK build or phone mutation.

## Release record

Record version, hook version, artifact paths, installation result, focused checks, actual phone evidence and remaining limits in CODEX_HANDOFF.md. Keep this guide short and update commands here when the build workflow changes.

### JBR25 collector crash workaround (121)

If the bundled JBR25 build daemon crashes in a parallel G1 GC thread with EXCEPTION_ACCESS_VIOLATION (for example android/hs_err_pid10368.log), adding `-XX:+UseSerialGC` to the existing Gradle JVM arguments completed the121 builds on this PC. This is a host build workaround, not an Android/runtime policy change. Preserve the crash evidence and distinguish JVM crashes from source compilation errors.
