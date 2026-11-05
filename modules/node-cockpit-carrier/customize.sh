#!/system/bin/sh
[ "$KSU" = true ] || abort "This backend requires KernelSU"
ui_print "Node Cockpit: Tunisia 5G profile"
ui_print "Stock /vendor remains unchanged; activation occurs after reboot"
set_perm_recursive "$MODPATH" 0 0 0755 0644
set_perm "$MODPATH/post-fs-data.sh" 0 0 0755
set_perm "$MODPATH/control.sh" 0 0 0755
set_perm "$MODPATH/cfg.db" 0 0 0644
