# 1.2.4+41

- Paired, disconnected Windows devices now show Connect and Unpair. Connected devices show Disconnect and Unpair.
- Windows audio Connect requests KSPROPERTY_ONESHOT_RECONNECT on the audio adapter matching the device's Bluetooth address. It does not open Settings or remove pairing.
- Missing audio profiles can be enabled on the active Bluetooth radio. Already-enabled drivers are left installed; the app does not uninstall/reinstall them to force reconnection.
- The app verifies remote connection state and reports failures instead of claiming a successful connection when only a request was accepted.

Validation: Flutter analysis and five Bluetooth tests pass. Tests cover valid Connect/Disconnect/Pair states, native compilation, Core Audio topology enumeration and native request layouts. Live reconnect did not succeed on the current Mibro pairing: its Windows PnP node reports CM_PROB_PHANTOM and the saved audio adapter is unavailable. A comparison against Windows' own Connect action is pending; successful end-to-end reconnect is not confirmed.

Installed 1.2.4+41 on the Samsung A36. Phone UI confirmed Connect + Unpair for the paired/disconnected earbuds. A live Connect action through the app returned Windows error -536870363 (audio adapter device instance unavailable); pairing was retained and state remained Disconnected.

Repeat live reconnect test: two attempts using the installed backend both returned -536870363 within 55 ms; ten subsequent state checks per attempt remained paired/disconnected. The Bluetooth PnP entry now reports OK / CM_PROB_NONE, so the earlier phantom entry is not sufficient to explain the continuing failure. The audio adapter lookup still fails; reconnect remains unresolved. No pairing was removed.
