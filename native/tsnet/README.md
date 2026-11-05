# Embedded tsnet transport

Android uses this app-owned tsnet node by default. It does not start a VPN service
or depend on the official Tailscale Android app. Desktop platforms retain direct TCP.
Settings → Tailscale provides sign-in, current state, addresses and an explicit
Direct TCP alternative for new connections. Existing SSH sessions retain their transport.

The identity is stored in Android `noBackupFilesDir/tsnet`, separate from Termux.
It survives app/process restarts and normal updates; clearing app data or uninstalling
removes it. No auth keys or SSH credentials are embedded in the Go library.

## API and ownership

Go `Node` exposes `Start`, `WaitReady`, `Status`, `Dial`, `Read`, `Write`,
`CloseConnection` and `Close`. `WaitReady` avoids a collision with Java's final
`Object.wait(long)` method. Kotlin exposes Flutter channel methods `start`, `wait`,
`status`, `dial`, `read`, `write`, `close` and `stop` on `remote_control/tsnet`.
Kotlin dispatches blocking calls to worker threads; results return on Android's main thread.

Each dial returns a process-unique handle. Reads and writes have deadlines, writes
handle partial sends, EOF is empty bytes, and read timeouts use `TSNET_READ_TIMEOUT`.
Closing a handle interrupts its read without shutting down another SSH connection.
The Dart `SSHSocket` adapter preserves binary data, orders writes and propagates errors.
SSH authentication, host-key checks, terminal handling and commands remain in dartssh2.

## Build

Pinned versions and checksums are in `go.mod` and `go.sum`:
Tailscale v1.104.0, Go 1.27.1, and the recorded golang.org/x/mobile revision.
The generated AAR includes ARM64 (A36) and x86-64 (emulators), minimum Android API 24.

With Go, JDK, Android SDK and NDK installed:

```powershell
./scripts/build_tsnet.ps1
flutter build apk --debug
```

The script also accepts `-GoExecutable`, `-AndroidSdk`, `-JavaDirectory` and
`-Targets`. It writes `android/app/libs/tsnet.aar`; this generated file is ignored.
Rebuild it whenever Go source or dependency versions change. Flutter Android builds
need that AAR; a source checkout alone is not sufficient. Tools/caches stay in `.tools`.

## Validation

```powershell
cd native/tsnet
go test ./bridge
cd ../..
flutter test test/tsnet_transport_test.dart
flutter analyze
flutter test integration_test/tsnet_smoke_test.dart --dart-define=TSNET_NATIVE_SMOKE=true --no-uninstall -d <android-device-id>
```

The smoke flag uses a separate Android application ID to protect the main app's data.
The native smoke test starts the actual Go node and checks its Android state/auth
URL. It does not prove remote SSH connectivity. To verify that on the A36:

1. Sign in under Settings → Tailscale and approve the node if the tailnet requires it.
2. Use the PC's Tailscale IP or MagicDNS name in the saved device address.
3. Keep the official Tailscale VPN off. Switch to mobile data, connect, and run `whoami`.
4. Check toggle polling and the persistent terminal through the same connection.
5. Restart the app, confirm the same Tailscale identity/IP returns without signing in,
   then reconnect. Test two simultaneous devices and disconnect one independently.

Upstream references: [tsnet](https://tailscale.com/docs/features/tsnet),
[Go mobile bindings](https://go.dev/wiki/Mobile).

## Temporary remote ADB

The existing app-owned node also supports one explicitly enabled incoming ADB
relay on tailnet TCP5555. `StartDebugRelay(localPort, permittedPC)` forwards only
to127.0.0.1 on the phone. The selected peer must use a Tailscale IP; all other
source addresses are rejected, in addition to tailnet ACL enforcement. Android
ADB authorization/TLS bytes pass through unchanged. Four concurrent connections
maximum;30-minute expiry closes listener and sockets. `StopDebugRelay`, node
`Close`, and process death terminate access. There is no public/LAN listener.
`DebugRelayStatus` exposes session/expiry/connection/error diagnostics only.

Android Settings → Tailscale → Remote ADB offers two modes: reuse an existing
Wireless debugging TLS listener without changing settings, or opt into temporary
root-managed loopback ADB for mobile data. The latter saves service state before
changing only `service.adb.listen_addrs` to `tcp:127.0.0.1:37127`, then restarts
adbd. Stop/expiry restores the old listener/service state if it is still owned by
this session; a subsequent external change is not overwritten. No boot scripts,
VPN, SystemUI, persistent properties, ADB authentication, or root-module settings
are changed. If Android kills the app, the private local listener may remain
until reboot or the next visit to this screen; the tailnet relay is gone. Saved
restoration state supports retry after root denial/failure. No background or
unattended reboot availability is promised by this temporary mode.

See `docs/REMOTE_ADB.md` for installation and connection instructions. The Go
relay has local socket tests, but Pixel root-property behavior needs device
validation after manually installing build105.

### Adjustable session duration (109)

StartDebugRelayWithDuration and SetDebugRelayDuration accept5..1440minutes;
the old StartDebugRelay still defaults to30minutes. An active duration change
sets a new deadline from now without closing sockets. DebugRelayStatus includes
durationMinutes and expiresAt; Kotlin reschedules its restoration timer from
that same deadline. The watcher receives coalesced deadline-change notifications
and serializes expiry with updates. Duration preference survives ordinary app
restarts, but active sessions remain opt-in and do not survive process death.
