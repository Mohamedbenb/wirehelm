# Remote ADB

Wirehelm can temporarily relay Android Debug Bridge (ADB) through its embedded Tailscale node. Android debugging authorization still applies.

## Start and stop a session

1. In Wirehelm, open **Settings → Tailscale** and sign in to its embedded node.
2. In **Remote ADB**, enter the Tailscale IP address of the computer allowed to connect and select a duration.
3. If Android wireless debugging is already available, use it as the local ADB listener. Otherwise, the supported Pixel root path can start one temporarily with KernelSU authorization.
4. Tap **Start remote ADB** and run the adb connect command shown by Wirehelm on the permitted computer. Accept Android’s debugging authorization prompt if it appears.
5. Tap **Stop / restore** when finished. Expiry also ends the session and attempts to restore the previous local ADB state.

The address in the connect command belongs to Wirehelm’s Tailscale node. Tailnet ACLs and the permitted-computer setting both apply.

## Session lifecycle

An active session uses a foreground service and a wake lock bounded by the session deadline. App replacement, force stop, reboot, or network loss can interrupt it. After an app update, reopen Wirehelm and start a new session. Use regular local ADB if you need to verify an update independently of the relay.

Temporary root mode installs tagged IPv4 and IPv6 ingress guards around the local listener. Cleanup restores the previous ADB state before removing those guards. If Wirehelm cannot verify cleanup, **Stop / restore** remains available to retry.

For troubleshooting, inspect the on-device connection diagnostics. Check the app node, ACL, permitted computer, local listener, and Android authorization separately. See the [behavior guide](BEHAVIOR_GUIDE.md#8-temporary-adb-tailnet-access-versus-root-cleanup) for lifecycle details.
