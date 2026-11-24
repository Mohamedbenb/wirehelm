# Edge panel shortcuts and action controls

## Shortcut capacity

In **Edit**, the panel shows the number of shortcuts used out of 12. Each app inside a folder counts as a shortcut. When the list is full, tapping or holding a new app in the **Add** catalog shows a prompt to remove a shortcut first. Existing shortcuts can still be rearranged. Tap **Save** to commit your edits.

## Controls page

Open the Edge panel and tap **Controls** above the shortcuts. Tap a row to open its controls in place. Back returns to the list, then to shortcuts. Use **Show in Edge panel** on the Wirehelm Smart bulb, Remote keyboard, Plasma text size, or Power controls page to change its visibility. Enabling a control uses the current device if no host has been selected. You can also edit the list in **Settings → Controls list** in the panel. Smart bulb, PC power, and PC text size are enabled by default. Remote keyboard is optional.

Select hosts under **UI features → Edge panel → Panel actions**. The bulb uses a Linux host where it is already configured. The PC host is a saved CachyOS device that supplies both PC pages. Remote keyboard has a separate desktop selection. Unconfigured pages show a shortcut to Panel actions.

- **Smart bulb** offers power, brightness, white temperature, hue, and saturation. Sliders update while you drag.
- **PC power** offers Lock, Unlock PC, Sleep, Lock & sleep, Restart, and Shut down. If Plasma is locked, Unlock PC asks you to authenticate on the phone before it unlocks and wakes the display. The page shows the selected PC and asks for confirmation before sending an action. If the PC requires interactive authorization, use Power in Wirehelm.
- **PC text size** reads the current Plasma font size and applies an adjustable value in half-point increments. You can also select the 10 pt default.
- **Remote keyboard** sends a text draft or common keys to the selected SSH desktop. The draft stays in the page until you tap Send text and is cleared when you leave. KDE Wayland uses the saved keyboard approval when available. If KDE prompts again, approve access on the PC while the panel is open.

The pages prefer an existing Wirehelm SSH connection for the selected device, with its saved endpoint, account, and verified host key. When none matches, the panel opens its own connection and can reuse it across pages on that host for up to 25 seconds of inactivity. Leaving the panel never disconnects the app’s session.

## Clipboard shelf shortcut

Use **Clipboard shelf → Shelf options → Add to Edge panel** to append Clipboard shelf to default Favorites. It preserves existing entries/folders, does not duplicate a shortcut already present in a folder, does not enable a disabled panel and reports a full 12-shortcut list rather than dropping another item. App-specific lists can override Favorites: add Clipboard shelf to those lists separately if needed.

The built-in destination is also available in the panel's **Edit → Add** catalog and Wirehelm's Favorites/app-specific shortcut picker. It supports normal placement, removal, reordering and folders. Its stored ID is `com.example.remote_control.clipboard_shelf`, a reserved built-in token resolved to Wirehelm's existing activity, not an installed package. Ordinary app launchers and exclusion lists are unchanged; the built-in is not offered as a foreground-app condition.

Both cold and warm launches open the shelf directly. Named routes reuse the existing app/engine and avoid stacking another copy when the destination is already on top. Other Flutter pages remain underneath for normal Back navigation. The shelf's change stream is shared across any simultaneously mounted shelf pages.

## Bottom actions

Open **UI features → Edge panel → Panel actions**, or hold a normal bottom action. The editor controls visibility/order of Edit, Windows, Capture, Clipboard and Settings, icon size (20–32 dp), labels and columns (automatic or 1–4). Save commits the draft; Back cancels. Reset restores toolbar defaults only. Clipboard is optional in the toolbar and hidden by default, preserving the original four actions.

Columns are capped by actual usable panel width to maintain 48 dp touch targets. The card adds its clipped overhang to both width and padding, so it cancels: usable width is configured panel width minus 24 dp horizontal padding. A 140 dp panel fits two columns; four needs at least 216 dp. The saved column count is an upper limit when the panel is too narrow. Long action sections scroll within a bounded footer, leaving space for shortcuts. Save/Cancel in editing and Back/Add in window mode remain available regardless of normal-action visibility. If Edit is hidden, the existing panel long-press still enters editing; Wirehelm's app settings remain available even with every action hidden.

Action and control glyphs use a 24-unit vector viewport, rounded joins, a thin continuous contrast edge, and a soft shadow. The glyph color follows the panel’s adaptive setting or its chosen text tone. Adaptive app icons retain their native artwork with a subtle shadow behind the app mask. Action rows use transparent, rounded pressed feedback and accessible labels. Titles, shortcut labels, toolbar text, search, folders, and control pages share the Favorites text outline and shadow. The panel/handle glass engines, materials and their saved parameters are unchanged. Configuration updates rebuild toolbar content, not the material backend.

Settings are stored in the independent `edgePanelActions` JSON field and included in Edge saved setups. Existing configurations default safely. The hook validates IDs, duplicates, sizes and dimensions; bad hook snapshots fall back to defaults. Unsupported Windows controls are omitted without rewriting the saved order.

## Ownership and validation

- `EdgeBuiltinShortcuts`: built-in resolution and bounded/idempotent Favorites addition.
- `EdgePanelController` / `EdgePanelIcon`: catalogs, folders, toolbar layout, icon drawing and long-press entry.
- `EdgeActionSettings`: bounded content/style parsing and width/footer rules.
- `LocalCustomization` / `IndicatorSettings`: persistence, publishing and content signatures.
- `MainActivity` / `app_shortcut_navigation.dart`: fixed destination intent and cold/warm Flutter routing.
- Edge settings opens the action editor. The clipboard shelf can add its shortcut directly to Favorites. [Edge settings](../lib/screens/edge_panel_screen.dart) · [Action editor](../lib/screens/edge_actions_screen.dart) · [Clipboard shelf](../lib/screens/clipboard_shelf_screen.dart)

Focused native checks cover ID compatibility, preserving folders, duplicates, full lists, invalid toolbar settings, narrow-panel bounds and saved-scope ownership. Widget checks cover cold/warm routing, duplicate suppression and draft Save/Cancel. Build/install/hook activation and actual panel appearance/touch behavior are separate checkpoints; live validation is pending.


## Build 314 deployment evidence

Build 314 is installed; its installed base.apk matches SHA-256 `5421fd32c0dc98bdedd14b749af2d2d7e9b867291777f5feeb0bba83d7d8dd4e`. One guarded reload activated hook 196, SystemUI 6600 → 12592, active with no error and synchronized revisions 5936/5936. The selected panel/handle material preferences exactly match their pre-update snapshot. Twenty-two focused checks pass: 12 native and 10 Flutter, with clean analysis. The frontend was freshly compiled with documented host-only serial-GC flags after intermittent host crashes; Android runtime settings are unchanged. Source/plugin/AOT freshness and original signer were verified. Evidence: ignored `build/edge-314-verification.json`.

The user has been asked to add/open the shelf shortcut and test saved action customization and appearance. Those live interactions and pixel-level material appearance remain unverified; matching stored material values is not a visual rendering test. No phone UI was controlled during deployment.
