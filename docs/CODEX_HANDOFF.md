# Wirehelm handoff

## Current source

The repository uses the Wirehelm name. Build 270 was verified on a Pixel 10 before the naming and fresh-checkout cleanup. Existing package and integration identifiers still use their original names for upgrade compatibility.

The edge panel defaults to Card Glass, and the collapsed handle supports live Native Glass. Clear’s white veil and Regular’s adaptive tone each default to zero. The controls remain separate from tint strength. Android owns the rendering of notifications, Quick Settings, brightness, and volume.

## Last device verification

Build 270 and hook 182 were confirmed through local ADB. The hook reported a matching settings revision and zero edge failures. The panel was closed during readback, so the tint change still needs a visual check with the panel open. The logs show another SystemUI start after the installer restart, with no corresponding crash event in the available buffer.

## Development references

- [Build and deployment](BUILD_AND_DEPLOY.md)
- [Feature ownership](CODE_MAP.md)
- [Edge materials and standalone lab](GLASS_FEATURE_STATUS.md)
- [Root file explorer](ROOT_FILE_EXPLORER.md), [notification ring](CAMERA_NOTIFICATION_RING.md), and [Notification Undo](NOTIFICATION_UNDO.md)
