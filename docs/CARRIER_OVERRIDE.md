# Firmware-local carrier override

The v3 backend ships a small Android DEX patcher, not a vendor database. The searchable app picker lists unambiguous carriers from the device database. Defaults are Tunisie Telecom (60502) and Orange Tunisia (60501); users can select one to 32 carriers. Carrier IDs and profile hashes are resolved from the device's own database rather than pinned to an OTA.

## Ownership and requirements

- `scripts/carrier/CarrierDatabaseTool.java`: read-only compatibility inspection, copy/patch/validation and stock backups.
- `modules/node-cockpit-carrier/`: KernelSU scripts, fixed vendor target, selected MCCMNC list and mount status.
- `scripts/package_customization.py`: compiles the standalone DEX and packages a code-only module. Requires a JDK, Android SDK platform and D8.
- App-side `LocalCustomization` and the carrier page manage installation, explicit enable/disable and status. Module ID and app signing identity are retained.

This is portable across compatible firmware databases, not universal support for every device, modem or carrier. It requires `/vendor/firmware/carrierconfig/cfg.db`, the supported three-column confmap schema, an unambiguous carrier_info identity for each selected MCCMNC, and a nonempty stock wildcard_5g profile. It refuses unsupported or ambiguous inputs. It does not unlock unsupported bands or bypass carrier provisioning. Selections persist separately in the private state directory across module updates. The picker supports carrier names and MCC/MNC searches, retaining selections across searches. There is no all-carrier automatic mode.

## Boot and recovery

The enabled module runs in KernelSU's [post-mount stage](https://kernelsu.org/guide/module.html#shell-scripts), after vendor overlays and before normal app startup. Each boot copies the currently visible vendor database into the private `/data/adb/node_cockpit_carrier` state directory. The helper resolves IDs and the profile, changes only the selected confmap mappings, preserves existing parents, checks SQLite integrity and compares every other typed database record and the schema. Preparation has an eight-second process timeout. Failure leaves the vendor target unmounted by this module.

The source remains unchanged. A hash-verified source backup is retained as `stock-backups/<sha256>.db`. Prepared files and their hash manifest publish atomically, with the manifest last. The shell verifies source/output hashes and selection before mounting. The replacement is a bind mount; restoring stock disables it for the next boot. No modem image or vendor partition is written.

Wirehelm restores disabled flags after KernelSU finishes installation, including its staged copy, because KernelSU can reset them while replacing a pending update. An update preserves an existing disabled override. Fresh installs are disabled. Finish installing the backend with a reboot, then enable it explicitly and reboot to activate. Enable performs a read-only preflight first. An older active backend must be restored to stock and rebooted before re-enabling the new one. Firmware eligibility for SystemUI hooks remains separate; this backend does not broaden that allowlist.

## Verification and limits

Ten local tests execute the production Java patcher through a host-only real-SQLite adapter. They cover changed IDs/profile hashes, parent and arbitrary data preservation, source backups, inspection without writes, incompatible schemas, ambiguous identities, trigger side effects and available CP3A/CP4A fixtures. The adapter does not validate Android app_process, SELinux, mount timing or radio behavior. Sixteen focused Flutter picker/health/capability checks cover retained selections, stale search results, empty selection, status and rejection paths. Shell syntax checks cover module scripts.

Remote ADB checks on CP4A passed Android app_process catalog and isolated preparation, with the vendor input hash unchanged and both SIMs still LTE. No live override was activated by those checks. At deployment the corrected module was staged disabled. Its shell status reports compatible=true; configure/status round-tripped saved selections while disabled and the default pair was restored. The user subsequently reported build 308 functional and validated. This closes the functional follow-up; exact post-activation mount hashes, boot timing and per-SIM radio telemetry were not independently recaptured. The report does not establish support for other devices or guarantee 5G availability. For future regressions, inspect prepare.log, manifest hashes, active mount and both SIM registrations.

Local host tests require pinned SQLite JDBC 3.46.1.0 and slf4j-api 2.0.13 JARs under ignored `build/carrier-host/`. Run `python test/carrier_database_test.py`. The test adapter is under `test/carrier_host/` and is never packaged in the module or APK.
