# Clipboard shelf

Open **Features → Clipboard shelf**. **Save copied items** is off by default. Enabling it captures subsequent text/image copies while the personal user is unlocked. The current clipboard is not imported. New screenshots can also be captured automatically as described below. Tap an entry to copy it, hold to view text or an image preview, and use the bookmark/delete controls to pin or remove it. Search matches full saved text or source package. Pinned-only filtering is available.

## Retention and privacy

Default history is 100 recent entries for seven days. Choose 50/100/200 and 1/7/30 days in **History and privacy**. Up to 25 pinned entries survive expiry and ordinary history clearing. Clear history has a separate, unchecked **Include pinned clips** option. Pausing capture retains history. Adding an excluded app affects future copies; delete existing entries separately.

Apps' sensitive-clipboard flag is always honored. Several common password-manager packages are excluded initially; additional launcher apps or a manually entered package can be excluded. Apps do not always flag private content, so this cannot promise automatic password detection. Unknown sources, locked-screen events, other current users, Wirehelm's own copies, non-text/non-image types and over-limit items are skipped. Only the first clipboard item is stored; HTML becomes plain text. SystemUI's clipboard overlay and Android's clipboard expiry retain their stock behavior; automatically copied screenshots use the same clipboard API.

Text is limited to 65,536 UTF-16 characters. Images require a finite readable content file, at most 8 MB and 50 million decoded pixels, with a supported Android decoder. Stream-only/unknown-size image providers are skipped. The original file is preserved, including animation; the shelf displays a small JPEG preview. Recent images and previews share a 64 MB budget, evicting oldest unpinned images when needed. Pins consume that budget. A full pinned budget can prevent new images being retained. Duplicate content moves the existing entry forward and preserves its pin.

Private SQLite history, original images and previews live in credential-protected `noBackupFilesDir/clipboard`, excluded from Android backup. History is not synchronized automatically. **Send to PC** explicitly sends only the selected item over an existing authenticated SSH/SFTP connection; clipboard content is not included in diagnostic logs or automatic cloud uploads. The image-copy action creates an independently readable cache snapshot so deleting shelf history does not immediately invalidate the currently copied image. These temporary exports are capped at 64 MB and cleaned after 24 hours on a subsequent image-copy action; Android may evict cache earlier. Only the current image URI is shared through Android's normal clipboard read grants. Clearing shelf history leaves the current Android clipboard alone.

Retention cleanup runs on a new stored copy or shelf access, without wakeup timers. Until the next access, expired data may still physically exist on disk. Removing the app removes its private storage; reinstalling an update preserves it.

## Capture and process ownership

`ClipboardShelfObserver` registers an event listener in the existing SystemUI hook, using SystemUI's privileged clipboard access. It checks opt-in, lock/user state, source exclusions and sensitive metadata before reading content. A bounded background worker handles capture without blocking the SystemUI main thread. No polling, foreground service or wake lock is added. Android's restrictions on ordinary background clipboard reads are not globally relaxed.

`ClipboardShelfProvider` runs on demand in `:clipboard`, without Flutter, Tailscale or main app root-safety initialization. Binder UID checks allow only Wirehelm to list/edit/copy history; the exact same-user SystemUI UID may read capture policy and submit bounded clips. The separate image FileProvider exposes only temporary copy snapshots and requires an Android URI grant for other apps. Main-app screen-off self-exit does not remove the SystemUI listener; a later event can recreate the native provider.

Hook 195 adds automatic screenshot publication capture and requires one SystemUI reload after installing build 313. Hook 194 supported copied items only. **SystemUI observer connected** records the most recent contact in the current boot, not a perpetual liveness guarantee. The initial contact does not capture clipboard content.

## Files and validation

- `android/customization/.../ClipboardShelfObserver.java`: event listener, source/sensitive guards, bounded worker.
- `android/app/.../clipboard/ShelfPolicy.kt`: opt-in, exclusion and retention limits.
- `ClipboardShelfStore.kt`: SQLite history, deduplication, pinning, bounded image storage and pruning.
- `ClipboardShelfProvider.kt`: UID-checked IPC, image snapshot export and copy actions.
- `lib/screens/clipboard_shelf_screen.dart`: feature page, history, search, controls and exclusion picker.
- `ShelfPolicyTest`: opt-in, lock/sensitive/self/excluded guards and bounded options.
- `clipboard_shelf_screen_test.dart`: capture consent, copy, native search and safe history clearing.
- `test/clipboard_shelf_store_test.py`: executes the production schema/list/retention SQL with Android-style string-bound parameters, covering normal and pinned history, literal search and pin-preserving expiry. Run directly with Python. This caught and prevents a TEXT `0` versus INTEGER `0` comparison regression.

Phone capture, image paste, exclusions, lock behavior and user-visible layout require device validation. A successful build or observer contact alone does not establish those behaviors.


## Build 312 activation

The first candidate installed successfully with one guarded activation reload, SystemUI PID 22843 → 31872. Hook 194 reports active, no error and revisions 5880/5880 synchronized. The recovery watchdog was healthy and unquarantined before the reload. The observer contacted its provider in boot 57; the native `:clipboard` process had no Flutter/Tailscale libraries loaded. An external shell UID was denied history access. Initial evidence: `build/clipboard-312-activation.json`.

Final app-only corrections fix the ordinary-history SQLite filter and clean failed image imports. The SystemUI observer is unchanged; no second reload is required. Four native policy tests, two Flutter tests and five production-SQL host checks pass; analyzer is clean. The user subsequently confirmed a harmless copied text appears in the shelf. Image paste and other UI interactions still need user verification; observer contact alone is not capture validation.


The final app-only candidate is installed, with its installed base.apk SHA-256 matching `d67b8a34589c63e91c3e2099e520aef89f292274b072075f9cd82ad25bbfa5c5`. SystemUI stayed PID 31872 / hook 194 throughout that correction. The restarted provider PID 18967 remains native-only, and an ordinary external shell UID is denied access. Final evidence: `build/clipboard-312-verification.json`. The user enabled capture and confirmed copied text appears in the shelf. Text capture is therefore user-validated. Image paste and live pin/delete/exclusion/lock behavior are not yet claimed validated.


## Screenshot capture (build 313)

**History and privacy → Automatically copy screenshots** defaults on when capture and images are enabled. The hook observes MediaStore publication events on external and external-primary image collections. On this Pixel, new screenshots are published by `com.android.systemui` in `Pictures/Screenshots/` with a capture timestamp. The gate requires that owner/folder, completed publication, a timestamp after observer startup and within the recent minute, the current personal user and an unlocked device. It does not scan/import old screenshots. Repeated notifications are coalesced and IDs are deduplicated in bounded memory; no polling service or wakeup alarm is added.

A saved screenshot is added to the shelf and copied to Android's clipboard, unless a newer explicit clipboard item has arrived since the screenshot was taken. Global capture, image and screenshot settings are checked before copying. Excluding System UI prevents screenshot capture. Other app exclusions do not infer which app's pixels are visible inside a screenshot. Disable this option independently if you want only explicitly copied items. The visible shelf receives private, package-scoped change events and refreshes without a permanent polling loop.

## Send to PC clipboard (build 313)

Every entry has **Send to PC**. Select a computer already connected in Devices; disconnected targets cannot receive an item. Text and supported images are placed in that computer's desktop clipboard, ready to paste. This is one explicit send, not continuous clipboard synchronization. Transfers claim a bounded app-work lease during SSH/SFTP work.

The selected payload is uploaded to a private, uniquely named temporary folder, never embedded in command text. Windows uses the existing interactive desktop helper in STA mode and Windows Forms clipboard APIs, with short retries for a busy clipboard. The computer must have a signed-in desktop; its installed image codecs must support the file. Linux uses `wl-copy` on a reachable Wayland session or `xclip` on X11; desktop environment/session access is required and has not yet been phone-tested. Other operating systems are not claimed supported.

Temporary payloads are removed after the attempt, using verified absolute roots and nonrecursive cleanup of only the known file/folder. An interrupted connection can leave a payload behind. A subsequent Windows send prunes strictly named folders older than a day; Linux relies on the normal temp cleanup if the final SSH cleanup could not run. Nothing is sent merely by taking a screenshot or opening the shelf.

## Image-copy correction (build 313)

The user showed an image successfully captured from Photos, but tapping Copy failed with missing `android.support.FILE_PROVIDER_PATHS` metadata. The image provider now declares `@xml/clipboard_paths` explicitly in the manifest; its no-argument FileProvider constructor and the static URI builder use that same declaration. A host regression check inspects the actual provider metadata and URI-grant scope. Image paste still needs a post-update user check.


Build 313 is installed with installed-APK checksum `c957990f33c458be80db9862fe047dcc77b25f3d5478f1aaf078e27f7288f1f7` verified. One guarded activation reload changed SystemUI 31872 → 6600; hook 195 reports no error and synchronized revisions 5880/5880. The last capture was screen-off/disabled while the phone was asleep. Observer contact 195 is recorded, the native provider PID 6871 has no Flutter/Tailscale libraries and external history access is denied. Capture, images and automatic screenshots are enabled. Nineteen focused checks pass: seven native policy/gate, six Flutter and six production-SQL/manifest checks. The generated Windows scripts parse; Windows PowerShell STA mode is confirmed. Actual PC clipboard contents were not modified/read by the agent, and screenshots were inspected only as MediaStore metadata. Post-update image paste, screenshot auto-capture and PC paste are awaiting the user's requested checks. Evidence: `build/clipboard-313-verification.json`.


## Edge access (build 314)

**Shelf options → Add to Edge panel** adds the direct shelf destination to default Favorites. It is also selectable in panel Edit/Add and app-specific lists, and can be enabled as a bottom action in the new [panel action customizer](EDGE_PANEL.md). App-specific rules can override default Favorites. Existing folders and material settings are preserved. The shortcut handles cold/warm app launches and keeps normal Back navigation.
