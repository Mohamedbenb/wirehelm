#!/system/bin/sh
set -eu
MODDIR=${0%/*}
TARGET=/vendor/firmware/carrierconfig/cfg.db
SOURCE="$MODDIR/cfg.db"
STATE=/data/adb/node_cockpit_carrier
EXPECTED=17faf3c27a4f8939f712eb280118e2b15fdef3ea7564ac921535cfcb1c1c3a6e
[ "$(id -u)" = 0 ] || exit 1

value() { printf 'carrier.%s=%s\n' "$1" "$2"; }
hash_file() { [ -f "$1" ] && sha256sum "$1" 2>/dev/null | awk '{print $1}' || true; }
mounted() { grep -F " $TARGET " /proc/self/mountinfo >/dev/null 2>&1; }

case "${1:-}" in
  status)
    value protocol 1
    value mode auto
    if [ -f "$MODDIR/remove" ]; then state=removalPending
    elif [ -f "$MODDIR/disable" ]; then state=disabled
    else state=enabled; fi
    value moduleState "$state"
    value moduleVersion "$(sed -n 's/^version=//p' "$MODDIR/module.prop" 2>/dev/null | head -n 1)"
    source_hash=$(hash_file "$SOURCE")
    target_hash=$(hash_file "$TARGET")
    value sourceFound "$([ -f "$SOURCE" ] && echo true || echo false)"
    value targetFound "$([ -f "$TARGET" ] && echo true || echo false)"
    value sourceHash "$source_hash"
    value targetHash "$target_hash"
    value configValid "$([ "$source_hash" = "$EXPECTED" ] && echo true || echo false)"
    if mounted; then value overrideMounted true; else value overrideMounted false; fi
    if mounted && [ "$source_hash" = "$EXPECTED" ] && [ "$target_hash" = "$EXPECTED" ]; then value overrideActive true; else value overrideActive false; fi
    value simOperators "$(getprop gsm.sim.operator.numeric 2>/dev/null)"
    value networkOperators "$(getprop gsm.operator.numeric 2>/dev/null)"
    value expectedHash "$EXPECTED"
    value pendingReboot "$([ -f "$STATE/enable_pending" ] && echo true || echo false)"
    if [ -f "$STATE/mount.log" ]; then value lastMount "$(tail -n 1 "$STATE/mount.log" | tr '\n=' '  ')"; fi
    # These vendor/Android fields are diagnostics only. Missing fields never
    # change backend health because coverage and framework output vary by build.
    dumpsys telephony.registry 2>/dev/null | sed -n \
      -e 's/.*isEnDcAvailable=\([^, }]*\).*/carrier.endcAvailable=\1/p' \
      -e 's/.*isNrAvailable=\([^, }]*\).*/carrier.nrAvailable=\1/p' \
      -e 's/.*mNrState=\([^, }]*\).*/carrier.nrState=\1/p' \
      -e 's/.*nrState=\([^, }]*\).*/carrier.nrState=\1/p' \
      -e 's/.*mNrFrequencyRange=\([^, }]*\).*/carrier.nrFrequencyRange=\1/p' \
      -e 's/.*mOverrideNetworkType=\([^, }]*\).*/carrier.overrideNetworkType=\1/p' \
      | awk -F= '!seen[$1]++'
    ;;
  enable)
    [ ! -f "$MODDIR/remove" ] || { echo 'Module is pending removal' >&2; exit 3; }
    rm -f "$MODDIR/disable"
    : > "$STATE/enable_pending"
    value pendingReboot true
    ;;
  disable)
    rm -f "$STATE/enable_pending"
    : > "$MODDIR/disable"
    value pendingReboot true
    ;;
  *) echo 'Unsupported operation' >&2; exit 2 ;;
esac
