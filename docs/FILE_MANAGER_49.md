# File manager — 1.5.0+49

Audio relay was retired: app UI, Dart service, bundled sender/receiver and relay-only tests were removed. On this installation the PC relay folder, Pi receiver folder, dedicated PC-to-Pi relay authorization and saved Mibro PipeWire latency override were removed. Bluetooth management remains. WirePlumber was not restarted; an already-applied runtime property can remain until its next restart.

Files now support previews (common text formats up to 256 KB; images up to 8 MB), rename, move, folder search, folder creation, persisted favorite folders, and queued uploads/downloads/copies between connected devices. Uploads use Android's document picker and reopen its URI for retry. Queue records show state, bytes and speed, with cancellation and retry.

Device copies stream through the phone using each device's authenticated SFTP connection. They do not use remote-to-remote SSH credentials or store an intermediate file on the phone. Connect both devices first. Directory-tree transfers, recursive search, resume after app termination and phone-independent server-to-server transfer are not implemented.

Uploads/copies exclusively create their destination and never truncate an existing file. Failed or cancelled transfers attempt to remove the file they created. A lost remote connection can prevent cleanup. Rename/move first check destination existence; the SFTP v3 rename operation cannot guarantee no replacement against a simultaneous external writer on every server. Avoid concurrent edits of the same destination.

Transfers belong to the open file-manager screen. Back requests confirmation and waits for pending transfer cancellation before closing its SFTP session. App termination/disconnection can interrupt work. Retry restarts a transfer from the beginning.

Validation: Flutter analyzer and targeted queue, upload, download and device-home tests. Live test results are recorded separately after phone verification.
