# Node Cockpit build 6

- Files: upload from Android's file picker into the current remote folder.
  Existing filenames are rejected rather than overwritten. Cancellation and
  failed uploads attempt to remove only the newly created partial file.
- Files: create folders, transfer MB/s and byte progress, retry downloads,
  and recent successful transfers while the file screen remains open.
- Downloads: 64 KB pipelined SFTP reads, 512 KB native write batches and
  buffered Android output. APK downloads receive the next batch while Android
  writes the previous one, with bounded buffering and verification preserved.
- Windows status: desktop and standard JSON batches run concurrently, so a
  slow desktop task does not delay the network-adapter batch. Desktop probes
  still use the existing hidden scheduled-task launcher and deduplicate scripts.
- Status errors: two-line card summary with full selectable Details.
- The terminal is unchanged.

Install through Settings → App updates. Performance changes take effect after
installing this build; the currently installed downloader handles this download.
The reported speed is an average including setup, not a phone-wide speed test.
No measured improvement over the user's mobile/Tailscale path is claimed until
tested on that connection. Recent transfers are not a background transfer manager.
