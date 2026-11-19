#!/system/bin/sh
[ "$KSU" = true ] || abort "KernelSU is required"
ui_print "Wirehelm firmware-local carrier backend"
ui_print "Uses the current vendor cfgdb; unsupported layouts stay stock"
# Installation does not silently enable an existing disabled override.
if [ -f /data/adb/modules/tn_5g_cfgdb_wildcard/disable ] || [ ! -d /data/adb/modules/tn_5g_cfgdb_wildcard ]; then touch "$MODPATH/disable"; fi
set_perm_recursive "$MODPATH" 0 0 0755 0644
set_perm "$MODPATH/post-fs-data.sh" 0 0 0755
set_perm "$MODPATH/post-mount.sh" 0 0 0755
set_perm "$MODPATH/control.sh" 0 0 0755
