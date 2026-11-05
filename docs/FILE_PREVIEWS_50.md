# File previews — 1.5.1+50

Tapping a JPEG, PNG, GIF, WebP, BMP or WBMP file opens a full-screen image preview with pinch zoom (up to 8x) and Download original. Image rows have an image icon. Preview download remains limited to 8 MB; larger originals can be downloaded. Unsupported image codecs show a readable fallback.

File rows, metadata dialogs and transfer progress use B/KB/MB/GB/TB as appropriate (1024-based units). Transfer speeds use the same units per second; unknown sizes are labeled explicitly. Folder sizes are not computed recursively.

Validation: Flutter analyzer clean; file-size/extension and transfer-queue tests passed. APK built and installation checked separately. No live image rendering test was claimed.
