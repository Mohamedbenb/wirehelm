# Node Cockpit build 8

- Keep Windows NetAdapter loaded globally in the persistent helper, including JSON batch probes and adapter actions. This avoids repeatedly autoloading the module in a short-lived script scope.
- Retain idle Windows helpers for five minutes; explicit disconnect still closes them.
- Add a direct **Test download speed** button to **Settings → App updates**, beside the download entry. Select the update source first. The test downloads and discards the APK without installing it, so it can run against the currently installed build.
- Show the actual connection route and host on the update download page.
- Keep the device information list above the Android navigation bar.

Validation: flutter analyze clean; all 70 tests passed. Real local Windows helper adapter requests measured 945 ms initially and 37/35 ms subsequently. These are local helper timings, not mobile end-to-end latency. No improvement to mobile download throughput is claimed for this release; the transfer pipeline is unchanged.
