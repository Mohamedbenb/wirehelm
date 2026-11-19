# Rooted OTA preparation

Open a connected computer's tools → **Prepare rooted OTA**, or choose **Prepare OTA** on a completed ZIP in Remote downloads. Work runs on the computer and continues after SSH disconnects. This feature creates a new ZIP; installation of firmware remains a separate operation.

## Setup

Use Python 3.9 or newer and a local output filesystem supporting hard links (NTFS/ext4). The setup folder contains `avbroot.exe`, `ksud-v<version>.exe` (or `ksud.exe`), `avb.key`, `ota.key`, `ota.crt`, and `avb_pkmd.bin`. On Unix, omit `.exe`. KernelSU's host utility must match the phone's installed official manager version. The current PC setup is `C:/avbroot-pixel10`, avbroot 3.37.0 and ksud 3.3.1.

Tap **Choose OTA ZIP** to browse folders and ZIP files on the computer. The picker lists files through the preparation worker's SSH command and starts in the selected ZIP's folder or the signing setup folder. If that starting folder is missing, it opens the remote account's home folder. A stalled request offers **Retry**. Select a full A/B OTA targeting the phone's device codename. Incremental packages and builds older than the phone's Build.TIME are rejected. Supply the original ZIP's SHA-256 from its official download page. A completed remote download carries its expected checksum into the form.

Inspect inputs, choose a new output name, and enter each encrypted key's passphrase. Keys remain on the computer. Passphrases travel through SSH stdin, bypassing the Windows command helper's disk-backed request queue. They are passed to signing subprocesses through environment variables and are not saved in job JSON or worker files. The fields clear after submission; retry requires entering them again. Local administrators can inspect a running signing process's memory/environment.

## Pipeline and ownership

`remote_downloads.dart` installs the Python workers. `remote_ota_worker.dart` owns persistent jobs in `~/.wirehelm/ota-preparation`; it reuses atomic JSON and locking from the download worker. `ota_preparation_screen.dart` displays status. The Android `otaDevice` bridge supplies device codename, build timestamp and KernelSU manager version.

The worker checks source SHA-256, source signatures, private/public key consistency and available disk space. If the setup includes `embedded-avb-pkmd.bin` or `embedded-ota.crt`, each must match its configured counterpart. It pins copies of the public AVB key and OTA certificate, extracts this OTA's boot/init_boot images, and uses KernelSU's scratch boot patch to detect KMI. It discards that probe and patches this OTA's init_boot with the detected KMI. avbroot signs the full OTA, then verifies its OTA and AVB signatures against the pinned public identities. Host-tool execution runs serially after inconsistent results with parallel verification on Windows. A verified output receives a SHA-256 and is published without overwriting an existing file.

Cancellation terminates the owned child and removes only the job's checked scratch directory. Host interruption leaves an interrupted job requiring a new preparation. There is no firmware flashing, bootloader mutation, automatic key generation, or persistent passphrase storage. Matching saved public keys does not independently prove which key is enrolled on the phone; the operator must retain the correct signing setup.

## After a firmware update

Successful OTA signature verification does not validate installed root modules against the new firmware. In particular, the optional Tunisia 5G backend 2.0.0 bundles an older vendor carrier database. Leave it disabled on CP4A.261105.040.A1 because it uses an older vendor configuration; its source checksum alone does not establish compatibility. The replacement v3 backend generates from the current firmware at boot and rejects unsupported layouts; see [carrier override](CARRIER_OVERRIDE.md). Validate cellular service separately after each firmware change. See the [current handoff](CODEX_HANDOFF.md) for the phone's carrier compatibility and recovery state.

## Focused checks

`test/remote_ota_worker_test.py` is opt-in: set `WIREHELM_OTA_FIXTURE` to a full stock OTA. It generates temporary encrypted keys and tests rejection, cancellation, patch/sign/verify, and credential-free journals. Real setup keys and source ZIP are unchanged. `remote_downloads_test.dart` covers both worker bootstraps and the Windows private stdin path. Device UI and actual firmware installation are separate validation boundaries.

Tool references: [avbroot](https://github.com/chenxiaolong/avbroot), [KernelSU installation](https://kernelsu.org/guide/installation.html).
