#!/system/bin/sh
set -eu
MODDIR=${0%/*}
[ "$(id -u)" = 0 ] || exit 1
. "$MODDIR/common.sh"
case "${1:-}" in
 status)
    value protocol 2
    value mode firmwareLocal
    if [ -f "$MODDIR/remove" ]; then state=removalPending; elif [ -f "$MODDIR/disable" ]; then state=disabled; else state=enabled; fi
    value moduleState "$state"
    value moduleVersion 3.0.0
    value targetFound "$([ -f "$TARGET" ] && echo true || echo false)"
    target_hash=$(hash_file "$TARGET")
    source_hash=$(hash_file "$PATCHED")
    expected=$(prop patchedHash)
    base=$(prop baseHash)
    value sourceFound "$([ -f "$PATCHED" ] && echo true || echo false)"
    value sourceHash "$source_hash"
    value targetHash "$target_hash"
    value baseHash "$base"
    value expectedHash "$expected"
    active=false
    if mounted && [ ${#expected} -eq 64 ] && [ "$source_hash" = "$expected" ] && [ "$(prop carriers)" = "$carriers" ] && [ "$target_hash" = "$expected" ]; then active=true; fi
    valid=false
    if [ ${#base} -eq 64 ] && [ ${#expected} -eq 64 ] && [ "$source_hash" = "$expected" ] && [ "$(prop carriers)" = "$carriers" ] && { [ "$target_hash" = "$base" ] || [ "$active" = true ]; }; then valid=true; fi
    if patcher inspect > "$STATE/inspect.log" 2>&1; then compatible=true; else compatible=false; fi
    value compatible "$compatible"
    value configValid "$valid"
    value overrideActive "$active"
    value overrideMounted "$(mounted && echo true || echo false)"
    value profileHash "$(prop profile)"
    value carrierIds "$(prop carrierIds)"
    value selectedCarriers "$carriers"
    value simOperators "$(getprop gsm.sim.operator.numeric)"
    value networkOperators "$(getprop gsm.operator.numeric)"
    value pendingReboot "$([ -f "$STATE/enable_pending" ] && [ "$(cat "$STATE/enable_pending")" = "$(cat /proc/sys/kernel/random/boot_id)" ] && echo true || echo false)"
    [ ! -f "$STATE/mount.log" ] || value lastMount "$(tail -n 1 "$STATE/mount.log")"
    ;;
 catalog)
    patcher catalog "${2:-q:}"
    ;;
 configure)
    selection=${2:-}
    case "$selection" in ''|*[!0-9,]*) echo 'Invalid carrier codes' >&2; exit 2;; esac
    patcher inspect "$selection" > "$STATE/inspect.log" 2>&1 || { echo 'Unsupported or ambiguous carrier selection' >&2; exit 3; }
    printf '%s\n' "$selection" > "$STATE/carriers.list.tmp"
    mv -f "$STATE/carriers.list.tmp" "$STATE/carriers.list"
    if [ ! -f "$MODDIR/disable" ]; then cat /proc/sys/kernel/random/boot_id > "$STATE/enable_pending"; fi
    value pendingReboot "$([ ! -f "$MODDIR/disable" ] && echo true || echo false)"
    ;;
 enable)
    [ ! -f "$MODDIR/remove" ] || exit 3
    mounted && { echo 'Restore stock and reboot before re-enabling' >&2; exit 3; }
    patcher inspect > "$STATE/inspect.log" 2>&1 || { echo 'Incompatible vendor database; see inspect.log' >&2; exit 3; }
    rm -f "$MODDIR/disable"
    cat /proc/sys/kernel/random/boot_id > "$STATE/enable_pending"
    value pendingReboot true
    ;;
 disable)
    rm -f "$STATE/enable_pending"
    : > "$MODDIR/disable"
    value pendingReboot true
    ;;
 *) exit 2;;
esac
