#!/system/bin/sh
MODDIR=${0%/*}
. "$MODDIR/common.sh"
rm -f "$STATE/enable_pending"
if [ -f "$MODDIR/disable" ] || [ -f "$MODDIR/remove" ]; then log 'inactive: disabled'; exit 0; fi
if mounted; then log 'refused: target already replaced by a file mount'; exit 1; fi
if ! patcher prepare > "$STATE/prepare.log" 2>&1; then log 'refused: incompatible vendor database or preparation failure'; exit 1; fi
base=$(prop baseHash)
expected=$(prop patchedHash)
[ ${#base} -eq 64 ] && [ ${#expected} -eq 64 ] && [ "$base" = "$(hash_file "$TARGET")" ] && [ "$expected" = "$(hash_file "$PATCHED")" ] || { log 'refused: source/output changed'; exit 1; }
chown 0:0 "$PATCHED"
chmod 0644 "$PATCHED"
context=$(ls -Zd "$TARGET" | awk '{print $1}')
chcon "$context" "$PATCHED" || exit 1
if mount --bind "$PATCHED" "$TARGET"; then log "active: base=$base patched=$expected"; else log 'failed: bind mount'; exit 1; fi
