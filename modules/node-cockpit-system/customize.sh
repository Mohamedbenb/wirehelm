#!/system/bin/sh
[ "$KSU" = true ] || abort "This backend requires KernelSU"
ui_print "Node Cockpit: recovery backend only; no system/vendor mounts"
set_perm_recursive "$MODPATH" 0 0 0755 0644
set_perm "$MODPATH/service.sh" 0 0 0755
set_perm "$MODPATH/control.sh" 0 0 0755
