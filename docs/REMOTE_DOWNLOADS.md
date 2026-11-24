# Remote downloads

Open a connected device, then choose **Tools → Files & updates → Remote downloads**. Select a connected destination device, paste an HTTP or HTTPS URL, choose an existing folder and filename, and optionally supply the source’s SHA-256 checksum. The folder picker can create a destination folder through SFTP.

The destination needs Python 3.9 or newer and a local filesystem supporting hard links, such as NTFS or ext4. Windows discovery checks PATH and registered Python installations, skips Microsoft Store aliases, and continues after a failed probe. Wirehelm installs a small standard-library worker under the remote account’s home directory at `.wirehelm/remote-downloads/`. Windows launches it with a hidden process that breaks away from the SSH job. Linux launches it in a new session. A host that refuses detachment reports the failure.

Downloads run on the selected computer after Wirehelm or SSH closes. Keep that computer awake and online. The journal on that computer owns progress and controls. Reconnect to refresh status, pause, resume, cancel, or open the completed file’s folder. Power loss or reboot interrupts the worker. Reopening the page detects the interruption and offers Resume.

Pause retains the hidden partial file and reservation in the destination folder. Cancel removes those two owned files. Resume uses HTTP Range and If-Range with a stored strong ETag or Last-Modified value. A changed resource or missing validator causes a full restart. A failed checksum also restarts on retry. Signed URLs may expire and require a new download with a fresh URL.

The final filename appears after the complete response and any requested checksum pass. Publication atomically refuses an existing destination. Without a supplied checksum, completion verifies the response length when the server provides it. HTTPS uses Python’s normal certificate verification.

The app polls only while its download page is visible and resumed. `remote_downloads.dart` owns the SSH request and response protocol. `remote_download_worker.dart` contains the portable Python worker. Downloads do not pass through the phone.

Run `python -m unittest discover -s test -p remote_download_worker_test.py -v` for isolated HTTP transfer regressions. `flutter test --no-pub test/remote_downloads_test.dart` checks URL validation and runs the actual Windows bootstrap with shell characters in paths and filenames. These host tests leave phone UI validation separate.
