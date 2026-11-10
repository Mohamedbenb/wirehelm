# Build artifact retention

Keep the canonical release and its checksum in `build/artifacts/`, along with a verified rollback and the latest standalone engine lab. Treat the current updater APK and its metadata as a pair. The updater version may lag the locally installed build. See the [handoff](CODEX_HANDOFF.md) for the current distinction.

`scripts/clean_generated_artifacts.ps1` defaults to a read-only preview. It lists numbered APK copies in `build/app/outputs/flutter-apk/` whose identically named archive in `build/artifacts/` matches both the recorded SHA-256 and the copy. Run with `-Execute` to remove the verified copies. Run with no builds or updates in progress.

The script leaves named archives, updater aliases, Gradle outputs, sidecars, exact-firmware inspection files, and toolchains in place. The Windows [Flutter AOT workaround](WINDOWS_FLUTTER_AOT_BUILD.md) depends on generated frontend inputs. Confirm those inputs before separately pruning caches.

Historical cleanup evidence lives in the [build 254 report](history/ARTIFACT_CLEANUP_BUILD_254.md).
