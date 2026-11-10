# App network controls

Tap **App manager** in Wirehelm’s main Features list and grant Wirehelm root access. The list contains visible, user-installed launcher apps that request Internet access. System apps, shared UIDs, Wirehelm, and the supported root and hook managers are protected.

The switch changes the app’s owner-profile UID rule in Android’s OEM deny chain. Wirehelm reads the native chain and UID table to verify the result. **Network blocked** means the rule is present and the chain is enabled. A saved rule that could not be applied shows as inactive. Use **Reapply saved rules** after restoring root access.

Changes take effect while the phone is running. Android enforces them independently of the Wirehelm process. Saved choices are reapplied after Android delivers boot completion. Before boot completion there can be a window without these rules. Wirehelm uses the app’s installation identity when reconciling saved rules and clears its old rule on full uninstall.

Choose **Allow for 5 minutes** on a verified Wirehelm block to temporarily lift it. Android’s exact alarm access is required for timed exceptions. **Block now** ends the exception early. A reboot ends timed exceptions when saved rules are restored. Android can delay alarms during idle, and revoking alarm or root access can interrupt automatic reblocking. Reopening App Manager reconciles overdue exceptions when root is available.

The firewall targets traffic attributed to the selected UID. A different app or system service can still send traffic on the selected app’s behalf. Wirehelm does not occupy the Android VPN slot.

Wirehelm leaves rules from other tools in place. If another tool has rules in the disabled chain, Wirehelm declines to enable it. An empty enabled deny chain permits traffic.
