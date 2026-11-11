#!/bin/sh
# Luma TV debloater - disables bloatware, ads and telemetry on Android TV,
# Google TV, Xiaomi PatchWall and Fire TV devices over ADB. Fully reversible.
#
#   ./debloat.sh --ip 192.168.1.50 --dry-run
#   ./debloat.sh --ip 192.168.1.50
#   ./debloat.sh --aggressive --set-launcher --disable-stock-launcher --compile
#   ./debloat.sh --restore backups/MIBOX4-20261111-153000.actions

set -u

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
LIST_DIR="$SCRIPT_DIR/lists"
BACKUP_DIR="$SCRIPT_DIR/backups"

ADB=${ADB:-adb}
IP=""
DEVICE="auto"
AGGRESSIVE=0
UNINSTALL=0
DRY_RUN=0
SET_LAUNCHER=0
DISABLE_STOCK=0
FAST_ANIM=0
COMPILE=0
REBOOT=0
RESTORE=""
YES=0
LUMA_PKG="app.luma.tvlauncher"
LUMA_ACTIVITY="app.luma.tvlauncher.MainActivity"
SERIAL=""
LUMA_EXPLICIT=0

usage() {
    cat <<EOF
Usage: $0 [options]
  --ip ADDR[:PORT]          connect over network (default port 5555)
  --adb PATH                adb binary (default: adb on PATH)
  --device NAME             auto | google-tv | android-tv-stock | xiaomi-patchwall | fire-tv
  --aggressive              also remove the 'aggressive' tier
  --uninstall               pm uninstall --user 0 instead of disable (needed on some Fire TVs)
  --dry-run                 show what would happen, change nothing
  --set-launcher            make Luma the default home app
  --disable-stock-launcher  disable the stock home screen (only if Luma is installed)
  --fast-animations         set system animation scales to 0.5
  --compile                 AOT-compile Luma for faster cold start
  --reboot                  reboot when done
  --restore FILE            undo a previous run using its .actions file
  --luma-package PKG        Luma package id (default $LUMA_PKG)
  -y, --yes                 don't ask for confirmation
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --ip) IP=$2; shift ;;
        --adb) ADB=$2; shift ;;
        --device) DEVICE=$2; shift ;;
        --aggressive) AGGRESSIVE=1 ;;
        --uninstall) UNINSTALL=1 ;;
        --dry-run) DRY_RUN=1 ;;
        --set-launcher) SET_LAUNCHER=1 ;;
        --disable-stock-launcher) DISABLE_STOCK=1 ;;
        --fast-animations) FAST_ANIM=1 ;;
        --compile) COMPILE=1 ;;
        --reboot) REBOOT=1 ;;
        --restore) RESTORE=$2; shift ;;
        --luma-package) LUMA_PKG=$2; LUMA_EXPLICIT=1; shift ;;
        -y|--yes) YES=1 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage; exit 2 ;;
    esac
    shift
done

if [ -t 1 ]; then
    C_OK=$(printf '\033[32m'); C_FAIL=$(printf '\033[31m'); C_SKIP=$(printf '\033[90m')
    C_DRY=$(printf '\033[36m'); C_WARN=$(printf '\033[33m'); C_RST=$(printf '\033[0m')
else
    C_OK=""; C_FAIL=""; C_SKIP=""; C_DRY=""; C_WARN=""; C_RST=""
fi

status() {
    case "$1" in
        OK) c=$C_OK ;; FAIL) c=$C_FAIL ;; SKIP) c=$C_SKIP ;; DRY) c=$C_DRY ;; WARN) c=$C_WARN ;; *) c="" ;;
    esac
    printf '%s[%-4s]%s %s\n' "$c" "$1" "$C_RST" "$2"
}

die() { status FAIL "$1"; exit 1; }

adb_cmd() {
    if [ -n "$SERIAL" ]; then "$ADB" -s "$SERIAL" "$@" </dev/null 2>&1 | tr -d '\r'
    else "$ADB" "$@" </dev/null 2>&1 | tr -d '\r'; fi
}
sh_cmd() { adb_cmd shell "$1"; }

is_failure() {
    printf '%s' "$1" | grep -Eqi 'failure|exception|error|not allowed|cannot|unknown package'
}

# ---------------------------------------------------------------- connect
command -v "$ADB" >/dev/null 2>&1 || die "adb not found. Install Android platform-tools or pass --adb /path/to/adb"

if [ -n "$IP" ]; then
    case "$IP" in *:*) SERIAL=$IP ;; *) SERIAL="$IP:5555" ;; esac
    status INFO "Connecting to $SERIAL (accept the prompt on the TV if one appears)..."
    status INFO "$("$ADB" connect "$SERIAL" 2>&1 | tr -d '\r')"
fi

DEV_COUNT=$(adb_cmd devices | grep -c "	device\$")
if [ -n "$SERIAL" ]; then
    adb_cmd devices | grep -q "^$SERIAL	device\$" || die "Device $SERIAL is not authorised. Enable network debugging on the TV."
elif [ "$DEV_COUNT" -eq 0 ]; then
    die "No authorised device found. Enable Developer options > USB/Network debugging on the TV."
elif [ "$DEV_COUNT" -gt 1 ]; then
    die "More than one device connected. Pass --ip to choose one."
fi

# ---------------------------------------------------------------- restore
if [ -n "$RESTORE" ]; then
    [ -f "$RESTORE" ] || die "Backup file not found: $RESTORE"
    status INFO "Restoring from $RESTORE"
    while read -r action pkg _rest; do
        case "$action" in
            disabled) out=$(sh_cmd "pm enable $pkg") ;;
            uninstalled) out=$(sh_cmd "cmd package install-existing $pkg") ;;
            *) continue ;;
        esac
        if is_failure "$out"; then status FAIL "$pkg  ($out)"; else status OK "restored $pkg"; fi
    done <<EOF
$(sed "1s/^$(printf '\357\273\277')//" "$RESTORE" | tr -d '\r')
EOF
    exit 0
fi

# ---------------------------------------------------------------- detect
MANUFACTURER=$(sh_cmd 'getprop ro.product.manufacturer')
MODEL=$(sh_cmd 'getprop ro.product.model')
SDK=$(sh_cmd 'getprop ro.build.version.sdk')
status INFO "Device: $MANUFACTURER $MODEL (SDK $SDK)"

TMP=$(mktemp -d 2>/dev/null || mktemp -d -t lumadebloat)
trap 'rm -rf "$TMP"' EXIT INT TERM

sh_cmd 'pm list packages' | sed -n 's/^package://p' | sort -u > "$TMP/installed"
[ -s "$TMP/installed" ] || die "Could not read the package list from the device."

has_pkg() { grep -qx "$1" "$TMP/installed"; }

# Luma can be installed as a release, .profile or .debug build
LUMA_BASE=$LUMA_PKG
if [ "$LUMA_EXPLICIT" -eq 0 ] && ! has_pkg "$LUMA_PKG"; then
    for v in "$LUMA_BASE.profile" "$LUMA_BASE.debug"; do
        if has_pkg "$v"; then LUMA_PKG=$v; break; fi
    done
fi
if has_pkg "$LUMA_PKG"; then status INFO "Luma: $LUMA_PKG"; else status INFO "Luma: not installed"; fi

PROFILES=""
if [ "$DEVICE" = "auto" ]; then
    has_pkg com.amazon.tv.launcher && PROFILES="$PROFILES fire-tv"
    has_pkg com.google.android.apps.tv.launcherx && PROFILES="$PROFILES google-tv"
    { has_pkg com.mitv.tvhome || has_pkg com.mitv.tvhome.atv; } && PROFILES="$PROFILES xiaomi-patchwall"
    if has_pkg com.google.android.tvlauncher || has_pkg com.google.android.leanbacklauncher || [ -z "$PROFILES" ]; then
        PROFILES="$PROFILES android-tv-stock"
    fi
else
    PROFILES=" $DEVICE"
fi
status INFO "Profiles: common,$(echo "$PROFILES" | sed 's/ /, /g; s/^,//')"

# merge lists -> tier|package|description
: > "$TMP/entries"
for f in common $PROFILES; do
    [ -f "$LIST_DIR/$f.txt" ] || continue
    grep -v '^[[:space:]]*#' "$LIST_DIR/$f.txt" | grep '|' | tr -d '\r' >> "$TMP/entries"
done

awk -F'|' '$1=="never"{print $2}' "$TMP/entries" > "$TMP/never"
for v in "$LUMA_BASE" "$LUMA_BASE.profile" "$LUMA_BASE.debug" "$LUMA_PKG"; do
    echo "$v" >> "$TMP/never"
done

TIERS="safe"
[ "$AGGRESSIVE" -eq 1 ] && TIERS="$TIERS aggressive"
if [ "$DISABLE_STOCK" -eq 1 ]; then
    if has_pkg "$LUMA_PKG"; then TIERS="$TIERS launcher"
    else status WARN "Luma ($LUMA_PKG) is not installed - refusing to disable the stock launcher."; fi
fi

: > "$TMP/targets"
for tier in $TIERS; do
    awk -F'|' -v t="$tier" '$1==t' "$TMP/entries" >> "$TMP/targets.all"
done
touch "$TMP/targets.all"
while IFS='|' read -r tier pkg desc; do
    grep -qx "$pkg" "$TMP/never" && continue
    grep -q "^[^|]*|$pkg|" "$TMP/targets" && continue
    has_pkg "$pkg" || continue
    printf '%s|%s|%s\n' "$tier" "$pkg" "$desc" >> "$TMP/targets"
done < "$TMP/targets.all"

COUNT=$(wc -l < "$TMP/targets" | tr -d ' ')
if [ "$COUNT" -eq 0 ]; then
    status INFO "Nothing to remove for the selected tiers."
else
    if [ "$UNINSTALL" -eq 1 ]; then verb_desc="uninstalled for user 0"; else verb_desc="disabled"; fi
    echo
    status INFO "$COUNT package(s) will be $verb_desc:"
    while IFS='|' read -r tier pkg desc; do
        printf '        %-11s %-55s %s\n' "$tier" "$pkg" "$desc"
    done < "$TMP/targets"
    echo
fi

if [ "$DRY_RUN" -eq 1 ]; then
    [ "$SET_LAUNCHER" -eq 1 ] && status DRY "would set home activity to $LUMA_PKG/$LUMA_ACTIVITY"
    [ "$FAST_ANIM" -eq 1 ] && status DRY "would set animation scales to 0.5"
    [ "$COMPILE" -eq 1 ] && status DRY "would compile $LUMA_PKG with -m speed"
    status DRY "Dry run only - no changes made."
    exit 0
fi

if [ "$YES" -ne 1 ] && [ "$COUNT" -gt 0 ]; then
    printf 'Continue? [y/N] '
    read -r answer </dev/tty || answer=""
    case "$answer" in y|Y|yes|YES) ;; *) status INFO "Aborted."; exit 1 ;; esac
fi

# ---------------------------------------------------------------- backup
mkdir -p "$BACKUP_DIR"
SAFE_MODEL=$(printf '%s' "$MODEL" | tr -c 'A-Za-z0-9_-' '_')
STAMP=$(date +%Y%m%d-%H%M%S)
SNAPSHOT="$BACKUP_DIR/$SAFE_MODEL-$STAMP.snapshot.txt"
ACTIONS="$BACKUP_DIR/$SAFE_MODEL-$STAMP.actions"
{
    echo "# $MANUFACTURER $MODEL SDK $SDK  $STAMP"
    echo "# --- disabled before run ---"
    sh_cmd 'pm list packages -d'
    echo "# --- all packages (incl. uninstalled for user) ---"
    sh_cmd 'pm list packages -u'
} > "$SNAPSHOT"
: > "$ACTIONS"
status OK "Backup saved: $SNAPSHOT"

# ---------------------------------------------------------------- remove
DONE=0; FAILED=0
while IFS='|' read -r tier pkg desc; do
    if [ "$UNINSTALL" -eq 1 ]; then
        out=$(sh_cmd "pm uninstall -k --user 0 $pkg")
        verb=uninstalled
        case "$out" in *Success*) ok=1 ;; *) ok=0 ;; esac
    else
        out=$(sh_cmd "pm disable-user --user 0 $pkg")
        verb=disabled
        ok=0
        case "$out" in *disabled*) is_failure "$out" || ok=1 ;; esac
    fi
    if [ "$ok" -eq 1 ]; then
        echo "$verb $pkg" >> "$ACTIONS"
        status OK "$verb $pkg"
        DONE=$((DONE + 1))
    else
        hint=""; [ "$UNINSTALL" -eq 0 ] && hint="  (try --uninstall for this device)"
        status FAIL "$pkg: $out$hint"
        FAILED=$((FAILED + 1))
    fi
done < "$TMP/targets"

# ---------------------------------------------------------------- tweaks
if [ "$SET_LAUNCHER" -eq 1 ]; then
    if has_pkg "$LUMA_PKG"; then
        out=$(sh_cmd "cmd package set-home-activity $LUMA_PKG/$LUMA_ACTIVITY")
        if is_failure "$out"; then status FAIL "set-home-activity: $out  (use --disable-stock-launcher instead)"
        else status OK "Luma set as home app"; fi
    else
        status WARN "Luma ($LUMA_PKG) is not installed - skipping --set-launcher."
    fi
fi

if [ "$FAST_ANIM" -eq 1 ]; then
    for k in window_animation_scale transition_animation_scale animator_duration_scale; do
        sh_cmd "settings put global $k 0.5" >/dev/null
    done
    status OK "Animation scales set to 0.5 (restore with 1.0 in Developer options)"
fi

if [ "$COMPILE" -eq 1 ]; then
    if has_pkg "$LUMA_PKG"; then
        status INFO "Compiling $LUMA_PKG (can take a minute)..."
        out=$(sh_cmd "cmd package compile -m speed -f $LUMA_PKG")
        case "$out" in *Success*) status OK "Luma compiled for speed" ;; *) status FAIL "compile: $out" ;; esac
    else
        status WARN "Luma ($LUMA_PKG) not installed - skipping --compile."
    fi
fi

echo
status INFO "Done: $DONE changed, $FAILED failed."
status INFO "Undo any time:  $0 --restore \"$ACTIONS\""

if [ "$REBOOT" -eq 1 ]; then
    status INFO "Rebooting..."
    adb_cmd reboot >/dev/null
else
    status INFO "Reboot the TV to free the memory those apps were using."
fi
