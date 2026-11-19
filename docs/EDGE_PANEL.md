# Edge panel shortcuts and action controls

## Clipboard shelf shortcut

Use **Clipboard shelf → Shelf options → Add to Edge panel** to append Clipboard shelf to default Favorites. It preserves existing entries/folders, does not duplicate a shortcut already present in a folder, does not enable a disabled panel and reports a full 12-shortcut list rather than dropping another item. App-specific lists can override Favorites: add Clipboard shelf to those lists separately if needed.

The built-in destination is also available in the panel's **Edit → Add** catalog and Wirehelm's Favorites/app-specific shortcut picker. It supports normal placement, removal, reordering and folders. Its stored ID is `com.example.remote_control.clipboard_shelf`, a reserved built-in token resolved to Wirehelm's existing activity, not an installed package. Ordinary app launchers and exclusion lists are unchanged; the built-in is not offered as a foreground-app condition.

Both cold and warm launches open the shelf directly. Named routes reuse the existing app/engine and avoid stacking another copy when the destination is already on top. Other Flutter pages remain underneath for normal Back navigation. The shelf's change stream is shared across any simultaneously mounted shelf pages.

## Bottom actions

Open **UI features → Edge panel → Panel actions**, or hold a normal bottom action. The editor controls visibility/order of Edit, Windows, Capture, Clipboard and Settings, icon size (20–32 dp), labels and columns (automatic or 1–4). Save commits the draft; Back cancels. Reset restores toolbar defaults only. Clipboard is optional in the toolbar and hidden by default, preserving the original four actions.

Columns are capped by actual usable panel width to maintain 48 dp touch targets. The card adds its clipped overhang to both width and padding, so it cancels: usable width is configured panel width minus 24 dp horizontal padding. A 140 dp panel fits two columns; four needs at least 216 dp. The saved column count is an upper limit when the panel is too narrow. Long action sections scroll within a bounded footer, leaving space for shortcuts. Save/Cancel in editing and Back/Add in window mode remain available regardless of normal-action visibility. If Edit is hidden, the existing panel long-press still enters editing; Wirehelm's app settings remain available even with every action hidden.

Icons share a 24-unit viewport, consistent two-unit strokes, rounded joins, centered sizing and spacing, with a symmetric settings gear and a clipboard glyph. Action rows use transparent, rounded, contrast-aware pressed feedback and accessible labels. Bottom-action vectors bypass the legacy multi-copy ink outline; their labels use a subtle shadow rather than that outline. Existing shortcut/title contrast protection is unchanged. The panel/handle glass engines, materials and their saved parameters are unchanged. Configuration updates rebuild toolbar content, not the material backend.

Settings are stored in the independent `edgePanelActions` JSON field and included in Edge saved setups. Existing configurations default safely. The hook validates IDs, duplicates, sizes and dimensions; bad hook snapshots fall back to defaults. Unsupported Windows controls are omitted without rewriting the saved order.

## Ownership and validation

- `EdgeBuiltinShortcuts`: built-in resolution and bounded/idempotent Favorites addition.
- `EdgePanelController` / `EdgePanelIcon`: catalogs, folders, toolbar layout, icon drawing and long-press entry.
- `EdgeActionSettings`: bounded content/style parsing and width/footer rules.
- `LocalCustomization` / `IndicatorSettings`: persistence, publishing and content signatures.
- `MainActivity` / `app_shortcut_navigation.dart`: fixed destination intent and cold/warm Flutter routing.
- `edge_actions_screen.dart`: draft editor; `local_customization_screen.dart` / `clipboard_shelf_screen.dart`: entry points.

Focused native checks cover ID compatibility, preserving folders, duplicates, full lists, invalid toolbar settings, narrow-panel bounds and saved-scope ownership. Widget checks cover cold/warm routing, duplicate suppression and draft Save/Cancel. Build/install/hook activation and actual panel appearance/touch behavior are separate checkpoints; live validation is pending.


## Build 314 deployment evidence

Build 314 is installed; its installed base.apk matches SHA-256 `5421fd32c0dc98bdedd14b749af2d2d7e9b867291777f5feeb0bba83d7d8dd4e`. One guarded reload activated hook 196, SystemUI 6600 → 12592, active with no error and synchronized revisions 5936/5936. The selected panel/handle material preferences exactly match their pre-update snapshot. Twenty-two focused checks pass: 12 native and 10 Flutter, with clean analysis. The frontend was freshly compiled with documented host-only serial-GC flags after intermittent host crashes; Android runtime settings are unchanged. Source/plugin/AOT freshness and original signer were verified. Evidence: ignored `build/edge-314-verification.json`.

The user has been asked to add/open the shelf shortcut and test saved action customization and appearance. Those live interactions and pixel-level material appearance remain unverified; matching stored material values is not a visual rendering test. No phone UI was controlled during deployment.
