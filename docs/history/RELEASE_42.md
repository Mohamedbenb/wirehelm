# 1.2.5+42

- Windows audio pairing now uses DeviceInformationCustomPairing so Windows installs the playback, headset and associated profile devices as well as saving the Bluetooth bond.
- Headphones pair without a user-entered code: ConfirmOnly is accepted, and a legacy fixed PIN request is answered internally with 0000. Code prompts remain for non-audio devices requiring user input.
- Paired, disconnected Windows devices have a Repair connection action. Confirmation explains that the pairing will be removed and recreated and asks the user to put the device in pairing mode.
- Audio Repair uses Windows UnpairAsync followed by custom pairing and Connect. Normal Connect/Disconnect retains pairing. The app verifies actual state; failed Repair refreshes state so Pair becomes available when the old bond has been removed.
- Pairing operations time out and cancel their pending Windows requests. The compiled helper stays in memory and compiler temporary files are removed.

Validation: Flutter analysis and five Bluetooth tests pass, including native and modern pairing backend compilation and state-dependent actions. Live Mibro tests: initial Disconnect/Connect with the user's fresh Windows pairing passed; legacy native repair saved a bond but failed to install usable audio devices. Modern custom pairing and the exact production Repair backend both passed without a code prompt. Windows PnP then showed healthy Mibro headphones/headset/media/profile nodes and the connection stayed established across twenty one-second checks. End-to-end phone-app validation follows below.

Installed 1.2.5+42 on the Samsung A36. End-to-end app test passed over LAN: Disconnect retained pairing; Repair displayed its confirmation, recreated the Mibro pairing without a code dialog, and returned Paired / Connected. A subsequent Disconnect / Connect cycle also passed. Earbuds were left paired and connected to Windows.
