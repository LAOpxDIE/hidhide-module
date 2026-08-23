#!/system/bin/sh
# HIDHide universal loader: detects which KPM engine is available and uses it.
#   1. ksud kpm        - KernelSU forks with native KPM (SukiSU-Ultra, ReSukiSU, ...)
#   2. kpatch kpm      - KPatch-Next module (stock KernelSU / KernelSU-Next / Magisk), also APatch
#   3. insmod .ko      - legacy LKM fallback (any root, per-kernel build)
# Usage:
#   load.sh                          # read config from hidhide.conf
#   load.sh "vid=0x.. pid=0x.. name=.. phys=.."   # explicit args (WebUI)
MODDIR=${0%/*}
CONF=$MODDIR/hidhide.conf
KPM=$MODDIR/hidhide.kpm
KO=$MODDIR/hidhide.ko

get_conf() { grep -E "^$1=" "$CONF" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"'; }

VID=$(get_conf TARGET_VID);  PID=$(get_conf TARGET_PID)
NAME=$(get_conf FAKE_NAME);  PHYS=$(get_conf FAKE_PHYS)

# vid=0 / missing = AUTO mode: use the built-in HID capability matcher.
# The current policy targets USB multi-touch digitizers regardless of VID/PID.
case "$VID"  in 0x[1-9a-fA-F]*) ;; *) VID=0 ;; esac
case "$PID"  in 0x*) ;; *) PID=0 ;; esac
case "$NAME" in *[!A-Za-z0-9_.-]*|"") NAME=goodix_ts ;; esac
case "$PHYS" in *[!A-Za-z0-9_./-]*|"") PHYS=i2c/1-005d ;; esac

ARGS="vid=$VID pid=$PID name=$NAME phys=$PHYS"
[ $# -gt 0 ] && ARGS="$1"   # explicit args from WebUI (already whitelisted there)

find_kpatch() {
    local p
    for p in /data/adb/modules/*/bin/kpatch /data/adb/ap/bin/kpatch; do
        [ -x "$p" ] && { echo "$p"; return 0; }
    done
    command -v kpatch 2>/dev/null
}

KP=$(find_kpatch)

# already loaded? (avoid duplicates on manual re-run / service.sh retry)
if ksud kpm list 2>/dev/null | grep -qi hidhide; then
    echo "ALREADY engine=ksud"
    exit 0
fi
if [ -n "$KP" ] && $KP kpm list 2>/dev/null | grep -qi hidhide; then
    echo "ALREADY engine=kpatch"
    exit 0
fi

if [ -f "$KPM" ]; then
    # --- engine 1: ksud with native KPM ---
    if ksud kpm list >/dev/null 2>&1; then
        ksud kpm unload hidhide 2>/dev/null
        if ksud kpm load "$KPM" "$ARGS"; then
            echo "OK engine=ksud args=$ARGS"
            exit 0
        fi
    fi
    # --- engine 2: KPatch-Next / APatch kpatch binary ---
    if [ -n "$KP" ] && [ -n "$($KP hello 2>/dev/null)" ]; then
        if $KP kpm load "$KPM" "$ARGS" 2>/dev/null || $KP kpm load "$KPM"; then
            echo "OK engine=kpatch($KP) args=$ARGS"
            exit 0
        fi
    fi
fi

# --- engine 3: legacy LKM ---
if [ -f "$KO" ]; then
    rmmod hidhide 2>/dev/null
    if insmod "$KO" target_vid=$VID target_pid=$PID fake_name=$NAME fake_phys=$PHYS; then
        echo "OK engine=lkm"
        exit 0
    fi
    echo "FAIL: insmod failed (kernel version mismatch?)"
    exit 1
fi

echo "FAIL: no KPM engine found - install KPatch-Next, or use SukiSU-Ultra/APatch"
exit 1
