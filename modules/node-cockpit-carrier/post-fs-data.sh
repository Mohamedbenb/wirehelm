#!/system/bin/sh
MODDIR=${0%/*}
TARGET=/vendor/firmware/carrierconfig/cfg.db
SOURCE="$MODDIR/cfg.db"
STATE=/data/adb/node_cockpit_carrier
EXPECTED=17faf3c27a4f8939f712eb280118e2b15fdef3ea7564ac921535cfcb1c1c3a6e
umask 077
mkdir -p "$STATE"
rm -f "$STATE/enable_pending"
log() {
  printf '%s %s\n' "$(date +%s)" "$*" >> "$STATE/mount.log"
  tail -n 40 "$STATE/mount.log" > "$STATE/mount.log.tmp" 2>/dev/null && mv "$STATE/mount.log.tmp" "$STATE/mount.log"
}

if [ -f "$MODDIR/disable" ] || [ -f "$MODDIR/remove" ]; then
  log "inactive: module disabled or pending removal"
  exit 0
fi
if [ ! -f "$TARGET" ] || [ ! -f "$SOURCE" ]; then
  log "failed: source or vendor target missing"
  exit 1
fi
actual=$(sha256sum "$SOURCE" 2>/dev/null | awk '{print $1}')
if [ "$actual" != "$EXPECTED" ]; then
  log "failed: source checksum mismatch"
  exit 1
fi
chown 0:0 "$SOURCE" 2>/dev/null
chmod 0644 "$SOURCE" 2>/dev/null
context=$(ls -Zd "$TARGET" 2>/dev/null | awk '{print $1}')
[ -z "$context" ] || chcon "$context" "$SOURCE" 2>/dev/null
if mount --bind "$SOURCE" "$TARGET"; then
  log "active: $actual"
else
  log "failed: bind mount returned $?"
  exit 1
fi
