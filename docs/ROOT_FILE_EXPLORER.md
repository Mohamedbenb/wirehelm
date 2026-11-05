# Root file explorer

Current implementation: Node Cockpit 1.37.61 / build 267. Open the phone dashboard → Root file explorer. This feature uses root directly and is independent of Vector, SystemUI hooks and paused glass work. No SystemUI restart is needed for explorer updates.

## Navigation and presentation

Breadcrumbs, direct paths, Shared storage / App data / Root customizations / Temp / Root edit backups shortcuts, current-folder search, pull-to-refresh, folders-first sorting (name/date/size, ascending/descending) and hidden files are supported. Rows use friendly owner names and formatted sizes. Properties explains numeric UID/GID and permissions, including symbolic/octal mode and owner/group/other access. Unknown IDs are labeled rather than guessed package names.

Back clears search first, then navigates to the parent folder, and exits at `/`. Toolbar Back follows the same rules. Dialogs close independently. Returning to a folder restores its scroll position. Dirty text asks before discarding; successful Save returns without another discard prompt. Loading is bounded and blocks navigation during the outstanding operation. Lists stop at 1,000 entries with an explicit notice; search only filters loaded entries.

Common Android folders have short descriptions while browsing and in directory Properties. View options → Android folder guide opens the complete reference. Descriptions are guidance, not guarantees that editing a folder is safe. Sources: [AOSP partitions](https://source.android.com/docs/core/architecture/partitions), [shared system images](https://source.android.com/docs/core/architecture/partitions/shared-system-image), [APEX](https://source.android.com/docs/core/ota/vendor-apex), and [Magisk module and boot-script guide](https://topjohnwu.github.io/Magisk/guides.html).

## Write access

Browsing starts read-only. Standard Unlock is available for canonical shared storage, individual app-data folders and `/data/local/tmp`. Advanced unlock adds other ordinary folders plus the specifically authorized `/data/adb` customization subtree. Normal Unlock still refuses `/data/adb`; Advanced unlock requires typing the exact canonical folder path, verified in native code.

Use Root customizations to open `/data/adb`, preferably enter the particular module/configuration folder, then Advanced unlock → enter its exact path → Unlock folder. This covers `/data/adb/modules`, boot-script folders and root-manager configuration under the same subtree. No other critical-path exception is enabled. System/vendor partitions, `/data/system*`, `/data/misc*`, package-installation storage, APEX, device/kernel interfaces, mount aliases and encryption metadata remain protected. Broad roots `/`, `/data` and user/app parent directories cannot be granted. The canonical-path boundary prevents `/data/adb_backup` from being treated as part of `/data/adb`; traversal into `/data/system` remains blocked.

Every grant lasts five minutes and applies to descendants of one folder. It is stored only in the app's native process using elapsed realtime, never as a saved global toggle. Lock, app pause/background, leaving the explorer, expiry or process death revoke it. The native bridge overwrites scope, advanced mode and directory identity from its private lease on every mutation; caller-supplied write flags cannot elevate a standard grant. Queued pre-lock requests cannot obtain a later lease. Already accepted operations may finish. An open editor becomes read-only on revocation while keeping unsaved text.

Each mutation requires confirmation. No remount, SELinux bypass, permission editor, command execution or permanent deletion is provided. Read-only filesystems and Android security restrictions can still refuse a granted operation. Symlink write targets/ancestors, special files, replaced scope inodes, stale entries and out-of-scope destinations are refused by the root worker too. These protections reduce mistakes; they are not an isolation boundary against hostile concurrent root/mount changes. Editing live app or root-manager data can break services, root access or boot.

## File operations and root-customization backups

- Preview/edit regular UTF-8 text up to 128 KiB; binary/NUL/invalid UTF-8 is refused. No new-file or permission editor is included.
- Copy individual regular files up to 32 MiB, or rename files/folders in the same folder. Existing destinations are not intentionally overwritten. Setuid/setgid file copy/edit and editing multiply-linked files are refused. New directories inherit parent owner, mode and SELinux label.
- Ordinary-folder Trash renames an entry into a hidden sibling; nothing is recursively deleted. Show hidden files and rename it to restore. Long names are abbreviated and require supplying the original name manually.
- Trash is disabled under `/data/adb`: hiding a module or script in the same watched directory is not a reliable way to disable it. Use the root manager's module controls. Explicit Rename/Copy remain user-confirmed operations; copying an executable into a boot-script folder can deliberately create another boot script.
- Saves verify identity and SHA-256, stage a separate file, preserve checked owner/mode/SELinux context, flush data, keep an original backup, recheck the original, then atomically replace. Metadata-preservation or cross-filesystem atomic-move failure refuses replacement. Unrelated xattrs/ACLs are not cloned. Backups are not a complete recovery plan for live system configuration.
- Ordinary edits keep a hidden sibling backup. For `/data/adb` edits, **staging files and original backups are kept outside the root-manager/module tree**, in the app's private `no_backup/root-file-backups` folder. This prevents automatically created copies from becoming extra module payloads or boot scripts. The root helper verifies that backup folder's canonical path, app UID and 0700 permissions. Native code supplies that destination; Flutter cannot override it. Root edit backups opens it for inspection. Each `.bak` has a `.bak.json` companion identifying original path, time and SHA-256. Restoring text is manual: inspect/copy the saved text and edit the original after unlocking its folder. There is no automatic cross-folder restore operation. App uninstall/data clearing removes these private backups.
- Backups/trash are not auto-purged. A late failed operation may leave a valid backup or a private staging file. Private staging artifacts are outside watched root-manager folders. No actual module/script is modified merely by browsing, granting access, testing policy or installing the app.

## Architecture

Flutter: `lib/screens/root_files_screen.dart`, `lib/services/root_files.dart`, `lib/utils/root_file_presentation.dart`, `lib/utils/root_folder_guide.dart`.

Native lifecycle/lease/transport: `RootFilesBridge.kt`, owned by `MainActivity`. Root worker/policy: `RootFileWorker.java` and `RootFilePolicy.java`. The only critical-path exception is `customizationPath` for `/data/adb` in Advanced mode; the default critical blocklist is retained.

The worker runs as UID 0 through `su -c` and `app_process`, using the installed APK classpath. The entry point is retained by ProGuard. Only the quoted installed APK path enters the command; user paths/text are bounded JSON on stdin. No exported provider/service/receiver or remote filesystem RPC was added. Operations use short-lived background processes, bounded output and a 20-second watchdog. No polling or permanent root daemon.

## Verification

`flutter test test/root_files_ui_test.dart --no-pub`: presentation, Back/search/editor behavior, narrow layout/larger text, exact typed confirmation, folder guide, root-customization shortcut/Trash exclusion and private-backup navigation through mocked channels. These are not physical-device gesture or appearance acceptance.

`python scripts/check_root_files_device.py --serial SERIAL [--port PORT]`: compile production Java plus the device harness and execute it as root. It creates/removes only its fresh UUID test tree and temporary JAR under `/data/local/tmp`. No real `/data/adb` contents are changed. Cases include the advanced-only subtree exception, traversal/prefix rejection, unrelated critical paths, canonical private-backup ownership/mode checks, original listing/edit/copy/backup behavior, symlinks and stale identities. Results: `build/root-files-checks/results.json`.

Installation uses `scripts/install_root_explorer.py --build BUILD --expected OLD --serial SERIAL [--port PORT]`: version/SHA checks and one-shot guard, with no SystemUI restart. Never replay a queued install. `scripts/verify_root_explorer.py --build BUILD --serial SERIAL [--port PORT] --advanced-check --customization-check` verifies actual version/log/same SystemUI PID and packaged helper flags for ordinary, protected and `/data/adb` folders, without writing customization files. It removes the temporary installer APK after success. Signed artifacts and evidence are under `build/artifacts` and `build/root-files-checks`.

Build 267 is installed and version-verified. The packaged helper reports `/data/adb` as Advanced-unlockable and normal-unlock-protected, with `/system` and `/proc` still protected. SystemUI PID stayed 9080 before/after installation; no restart was requested. The temporary installer APK was removed. 28 isolated backend checks and 13 UI checks passed; analysis and release checks passed. User-facing validation remains separate.

Artifact: `build/artifacts/Node-Cockpit-1.37.61-build267.apk`, SHA-256 `fe3037b13a6327f07ca5b480c23c9165457e1c60de0f9e382a8053559d714991`. Readback evidence: `build/root-files-checks/installed267.json`. Never replay a completed installer.
