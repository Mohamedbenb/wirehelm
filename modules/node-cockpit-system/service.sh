#!/system/bin/sh
# KernelSU controls startup. No independent init/service.d entry points or module re-enabling.
MODDIR=${0%/*}
STATE=/data/adb/node_cockpit_system
umask 077
mkdir -p "$STATE"
while [ "$(getprop sys.boot_completed)" != 1 ]; do
 [ ! -f "$MODDIR/disable" ] && [ ! -f "$MODDIR/remove" ] || exit 0
 sleep 5
done
previous=""
window=$(date +%s)
count=0
last_revision=""
echo 0 > "$STATE/restarts"
while [ ! -f "$MODDIR/disable" ] && [ ! -f "$MODDIR/remove" ]; do
 now=$(date +%s)
 echo "$now" > "$STATE/watchdog_at.tmp"
 mv "$STATE/watchdog_at.tmp" "$STATE/watchdog_at"
 current=$(pidof com.android.systemui 2>/dev/null)
 enabled=$(sed -n 's/^enabled=//p' "$STATE/config" 2>/dev/null)
 revision=$(sed -n 's/^revision=//p' "$STATE/config" 2>/dev/null)
 if [ "$enabled" != 1 ] || [ "$revision" != "$last_revision" ]; then
  count=0; window=$now; previous="$current"; last_revision="$revision"
  echo 0 > "$STATE/restarts"
 fi
 if [ -n "$current" ] && [ -n "$previous" ] && [ "$current" != "$previous" ]; then
  if [ $((now-window)) -gt 120 ]; then window=$now; count=0; fi
  count=$((count+1))
  echo "$count" > "$STATE/restarts"
  # Process restarts are conservatively treated as suspect; never restart SystemUI ourselves.
  if [ "$count" -ge 3 ] && [ ! -f "$STATE/quarantine" ]; then
   "$MODDIR/control.sh" disable crashloop
   /system/bin/am broadcast --user 0 -a com.nodecockpit.customization.DISABLE \
    -n com.example.remote_control/com.nodecockpit.customization.RecoveryReceiver >/dev/null 2>&1 || true
   echo "$now repeated_systemui_restarts" >> "$STATE/recovery.log"
   tail -n 30 "$STATE/recovery.log" > "$STATE/recovery.tmp"
   mv "$STATE/recovery.tmp" "$STATE/recovery.log"
  fi
 fi
 [ -z "$current" ] || previous=$current
 sleep 5
done
rm -f "$STATE/watchdog_at"
