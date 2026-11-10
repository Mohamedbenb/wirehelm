# Build artifacts and cache retention

## Cleanup performed 2026-11-03

User authorized project cleanup after a measured37.839GiB inventory. The workspace is now7.146GiB, reclaiming30.692GiB (32,955,780,621 bytes). APK count fell from246 to24; other retained APKs include tool/dependency fixtures outside root/build cleanup scope. No source, signing configuration/material, application data, device state or installed app was changed.

Deleted222 obsolete root/build APKs and247 associated sidecars;156 obsolete Flutter build-cache directories; generated Flutter test cache; Go compilation cache; regenerable merged native libraries;15 old ring frontend intermediates. Deleted643 selected entries, with0 failures. Downloaded Gradle dependencies/distribution, Go toolchain/module sources, native Android inputs, diagnostics, screenshots, experiments and source remain. Remaining space is principally offline dependencies and retained build/evidence data, not application source.

Evidence: build/maintenance/cleanup-20261103-181428-plan.json and matching-result.json, plus cleanup-20261103-sizes.json. The result verifies19 critical retained files against their BEFORE-cleanup SHA256 hashes. Accepted254 APK passes scripts/verify_customization_apk.py; updater metadata remains version1.37.48/build254. A full rebuild was intentionally not run to repopulate cleared caches; no code/runtime change required one.

## Retained release artifacts

- Accepted production release: build/artifacts/Node-Cockpit-1.37.48-build254.apk and checksum/metadata sidecars. SHA256293d23b04ba82ef1d96bdb721d733f14d0b51459bea3bd0821d8b95fa22ffd47.
- One prior stable rollback: build/artifacts/Node-Cockpit-1.37.46-build252.apk and sidecars (ring before automatic ambient mode).
- Latest engine lab: build/artifacts/Glass-Engine-Lab-1.5.2-dev-build12.apk and checksum. Engine/glass implementation remains paused; retaining this does not authorize work on it.
- Current build/app/outputs/flutter-apk numbered254 APK, app-debug.apk/app-release.apk/node-cockpit-update.apk updater aliases and sidecars, plus build/app/outputs/apk/release/app-release.apk. The debug-named updater alias intentionally contains the current RELEASE APK. All retained Node updater payload hashes match the canonical254 archive.
- Exact-firmware inspection APKs and framework.jar remain available for future phone investigations.

Old APK paths in historical logs/docs and old artifact*.json records are historical evidence, NOT available downloads. Removed archives were intentionally retired; do not waste investigation trying to locate/reinstall them. Current source and the retained254/252 artifacts are the baseline. Ring feature remains user-accepted complete, with production bug discovery only.

## Build-workaround inputs must survive cleanup

This Windows host uses scripts/compile_android_frontend.py because normal Flutter JIT launching is unreliable. Do not blindly delete .dart_tool or run flutter clean as a substitute for the scoped cleanup. Preserve:

- .dart_tool/package_config.json and Android Dart plugin registrant at .dart_tool/flutter_build/dart_plugin_registrant.dart;
- verified native-assets map .dart_tool/flutter_build/fcb34e5a82cfb429eb2d277eb1931ace/native_assets.json and its pinned cache directory;
- current registered Android AOT254 intermediates and staged app.so;
- android/app/libs/tsnet.aar and native build inputs;
- toolchains, downloaded dependencies and signing inputs. Release currently uses Android's debug signing configuration; no key files or Android home state were touched.

Compile FRESH registered Android AOT after any frontend/source change, as before. Retained app.so is not permission to package stale code. Cleared native/test/Go compilation caches regenerate on demand; their next build may take longer.

## Future retention policy

At each accepted release, retain one canonical accepted Node APK, one explicitly chosen stable rollback, latest engine lab APK, current updater aliases/sidecars, current required frontend/native inputs, useful diagnostic evidence and source. Do not keep every numbered release in both root and outputs. Retire obsolete APK copies after the new release is accepted and verified. Historical text/JSON/checksum evidence can remain without their large binaries.

scripts/clean_generated_artifacts.ps1 defaults to a dry run for the CURRENT254 milestone; -Execute applies a reviewed plan. It rejects source-version mismatches, missing/mismatched accepted/rollback/updater hashes, missing required inputs, outside-workspace paths and reparse points, and rechecks preserved hashes afterward. It never deletes the entire project/build/.dart_tool tree. Operations use native PowerShell literal paths; no cross-shell deletion or process termination.

Run only with no builds active. Before using it for a future milestone, update/review accepted and rollback builds AND pinned frontend/native input paths for that release; do not merely assume254's inputs cover new dependencies or another frontend output location. The source-build guard intentionally prevents blind reuse after version changes. Review the generated manifest before -Execute. Dependency caches should only be purged separately when redownload/rebuild cost is acceptable. Never auto-run destructive cleanup from a phone installer or acceptance workflow.
