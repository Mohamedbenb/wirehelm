#!/system/bin/sh
# Do not remove backups/recovery evidence automatically. Remove only live heartbeat.
rm -f /data/adb/node_cockpit_system/watchdog_at
