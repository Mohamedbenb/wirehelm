#!/system/bin/sh
TARGET=/vendor/firmware/carrierconfig/cfg.db
STATE=/data/adb/node_cockpit_carrier
PATCHED="$STATE/patched.db"
MANIFEST="$STATE/prepared.properties"
umask 077
mkdir -p "$STATE"
chmod 0700 "$STATE"
value() { printf 'carrier.%s=%s\n' "$1" "$2"; }
hash_file() { [ -f "$1" ] && sha256sum "$1" 2>/dev/null | awk '{print $1}' || true; }
mounted() { grep -F " $TARGET " /proc/self/mountinfo >/dev/null 2>&1; }
prop() { [ ! -f "$MANIFEST" ] || sed -n "s/^$1=//p" "$MANIFEST" | head -n 1; }
if [ -f "$STATE/carriers.list" ]; then carriers=$(cat "$STATE/carriers.list"); else carriers=$(cat "$MODDIR/carriers.list"); fi
case "$carriers" in ''|*[!0-9,]*) echo 'Invalid carrier selection' >&2; exit 1;; esac
patcher() {
    expected=$(cat "$MODDIR/patcher.sha256")
    [ ${#expected} -eq 64 ] && [ "$(hash_file "$MODDIR/patcher.jar")" = "$expected" ] || return 1
    if [ "$1" = catalog ]; then
        CLASSPATH="$MODDIR/patcher.jar" timeout -s KILL 8 app_process / com.nodecockpit.carrier.CarrierDatabaseTool catalog "$TARGET" "$STATE" "$2" "$carriers"
    else
        CLASSPATH="$MODDIR/patcher.jar" timeout -s KILL 8 app_process / com.nodecockpit.carrier.CarrierDatabaseTool "$1" "$TARGET" "$STATE" "${2:-$carriers}"
    fi
}
log() { printf '%s %s\n' "$(date +%s)" "$*" >> "$STATE/mount.log"; }
