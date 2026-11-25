# Updating Wirehelm away from home

Publish a higher build code using the [build and deployment guide](BUILD_AND_DEPLOY.md). Keep the signing key and Android package unchanged. The desktop must stay online and reachable through the phone’s saved SSH or Tailscale connection.

1. Open **Settings → App updates** on the phone and choose the device hosting the APK.
2. On a Linux host, enter the full path to `build/app/outputs/flutter-apk/node-cockpit-update.apk` inside the checkout. Windows hosts start with `C:/remote_control/build/app/outputs/flutter-apk/node-cockpit-update.apk`. Wirehelm saves your chosen path for that device when you start the download.
3. Tap **Install update** after verification and confirm in Android’s installer. Android may first ask you to allow Wirehelm to install apps.

Wirehelm checks the package, signing certificate, version code, and downloaded size before installation. The Devices page uses the adjacent `.apk.json` to check for a newer build on an already connected source. Keep the metadata and APK together when publishing or moving an update.

For relay behavior across upgrades, see [Remote ADB](REMOTE_ADB.md). For deployment verification, see the [behavior guide](BEHAVIOR_GUIDE.md#9-update-and-deployment-success-boundaries).
