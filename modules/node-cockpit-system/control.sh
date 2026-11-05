#!/system/bin/sh
set -eu
MODDIR=${0%/*}
STATE=/data/adb/node_cockpit_system
umask 077
[ "$(id -u)" = 0 ] || exit 1
mkdir -p "$STATE"
numeric() { case "$1" in ''|*[!0-9]*) exit 2 ;; esac; [ "${#1}" -le 16 ] || exit 2; }
case "${1:-}" in
 status)
  echo protocol=1
  if [ -f "$MODDIR/disable" ]; then echo moduleState=disabled
  elif [ -f "$MODDIR/remove" ]; then echo moduleState=removalPending
  elif [ -f "$STATE/watchdog_at" ]; then echo moduleState=healthy
  else echo moduleState=notRunning; fi
  echo moduleVersion=1.0.0
  [ ! -f "$STATE/watchdog_at" ] || echo watchdogAt="$(cat "$STATE/watchdog_at")"
  [ ! -f "$STATE/restarts" ] || echo systemUiRestarts="$(cat "$STATE/restarts")"
  [ ! -f "$STATE/config" ] || cat "$STATE/config"
  if [ -f "$STATE/quarantine" ]; then echo quarantined=true; echo quarantineReason="$(cat "$STATE/quarantine")"; else echo quarantined=false; fi
  ;;
 apply)
  [ "$#" = 3 ] || exit 2
  numeric "$2"; numeric "$3"
  [ "$3" = 0 ] || [ "$3" = 1 ] || exit 2
  [ ! -f "$MODDIR/disable" ] && [ ! -f "$MODDIR/remove" ] || exit 3
  [ ! -f "$STATE/config" ] || cp "$STATE/config" "$STATE/previous"
  printf 'revision=%s\nenabled=%s\n' "$2" "$3" > "$STATE/config.tmp"
  mv "$STATE/config.tmp" "$STATE/config"
  # Clearing OUR quarantine is only done by an explicit apply; never touch KSU disable flags.
  rm -f "$STATE/quarantine"
  echo applied
  ;;
 disable)
  reason=${2:-user}
  [ "$reason" = user ] || [ "$reason" = crashloop ] || exit 2
  printf 'revision=0\nenabled=0\n' > "$STATE/config.tmp"
  mv "$STATE/config.tmp" "$STATE/config"
  echo "$reason" > "$STATE/quarantine"
  /system/bin/am broadcast --user 0 -a com.nodecockpit.customization.DISABLE -p com.android.systemui >/dev/null 2>&1 || true
  echo disabled
  ;;
 *) echo 'Unsupported operation' >&2; exit 2 ;;
esac
