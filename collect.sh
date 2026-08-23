#!/system/bin/sh
# HIDHide diagnostic collector.
# Collects everything needed to verify the disguise, writes a timestamped
# report with an innocuous filename (no "hid" in the path: a scanner
# sweeping shared storage must not find self-evidence).
# Primary copy lives in the module log dir; a public copy goes to the
# Download folder via the first reachable path of the fallback chain
# (/storage/emulated/0/Download -> /sdcard/Download -> module logs only).
MODDIR=${0%/*}
[ -d "$MODDIR" ] || MODDIR=/data/adb/modules/hidhide
CONF=$MODDIR/hidhide.conf
LOGDIR=$MODDIR/logs
mkdir -p "$LOGDIR" 2>/dev/null

# shared-storage target with fallback chain: the su/service mount
# namespace may lack the /sdcard bind, and with the screen locked (FBE
# direct-boot) emulated storage is entirely unavailable -> in that case
# the report lives in the module log dir only.
OUTDIR=""
for d in /storage/emulated/0/Download /sdcard/Download; do
    if [ -d "$d" ] && touch "$d/.wtest" 2>/dev/null; then
        rm -f "$d/.wtest"; OUTDIR="$d"; break
    fi
done

TS=$(date +%Y%m%d-%H%M%S)
OUT=$LOGDIR/device-diag-$TS.txt

get_conf() { grep -E "^$1=" "$CONF" 2>/dev/null | head -1 | cut -d= -f2- | tr -d '"'; }
VID=$(get_conf TARGET_VID);  PID=$(get_conf TARGET_PID)
NAME=$(get_conf FAKE_NAME);  PHYS=$(get_conf FAKE_PHYS)
[ -z "$NAME" ] && NAME=goodix_ts
[ -z "$PHYS" ] && PHYS=i2c/1-005d

# auto mode: vid missing / 0 / 0x0 / 0x0000
AUTO=1
case "$VID" in
    ""|0|0x0|0x00|0x000|0x0000) AUTO=1 ;;
    *) AUTO=0 ;;
esac

# Reports may be shared for support. Remove input-device unique identifiers by
# default; model/kernel information can still identify a device, so the report
# carries an explicit review warning below.
DEVS=$(cat /proc/bus/input/devices 2>/dev/null | sed 's/^U: Uniq=.*/U: Uniq=<redacted>/')

# does the block containing Name="$NAME" show Bus=0018 (I2C)?
name_is_i2c() {
    echo "$DEVS" | awk -v n="Name=\"$NAME\"" '
        BEGIN { RS="" }
        index($0, n) { if ($0 ~ /Bus=0018/) found=1 }
        END { exit !found }'
}

# explicit mode: is the original VID/PID still visible on USB?
VIDH=$(echo "$VID" | sed 's/^0x//i' | tr 'A-F' 'a-f' | sed 's/^0*//')
[ -z "$VIDH" ] && VIDH=0

# any external USB input devices left?
USB_LEFT=$(echo "$DEVS" | grep -c "Bus=0003")

if name_is_i2c; then
    VERDICT="PASS  - target HID device now presents as builtin input ($NAME, I2C)"
elif [ "$AUTO" = "0" ] && echo "$DEVS" | grep "Bus=0003" | grep -qi "Vendor=0*$VIDH "; then
    VERDICT="FAIL  - target still registered as EXTERNAL USB (re-plug the screen)"
elif [ "$USB_LEFT" -gt 0 ]; then
    VERDICT="REVIEW - $USB_LEFT external USB input device(s) visible; re-plug the target HID device and regenerate"
else
    VERDICT="NOT_FOUND - no matching external HID device seen (unplugged?)"
fi

{
echo "===== input diagnostic report ====="
echo "privacy: review model, kernel and device details before sharing"
echo "date:    $(date)"
echo "device:  $(getprop ro.product.model)"
echo "android: $(getprop ro.build.version.release) (sdk $(getprop ro.build.version.sdk))"
echo "kernel:  $(uname -r)"
echo
echo "--- module status ---"
[ -f "$MODDIR/hidhide.kpm" ] && echo "module file: hidhide.kpm (KPM)"
[ -f "$MODDIR/hidhide.ko" ]  && echo "module file: hidhide.ko (LKM)"
ENGINE="none"
if ksud kpm list >/dev/null 2>&1; then
    ENGINE="ksud (native KPM)"
else
    for p in /data/adb/modules/*/bin/kpatch /data/adb/ap/bin/kpatch; do
        [ -x "$p" ] && [ -n "$($p hello 2>/dev/null)" ] && { ENGINE="kpatch ($p)"; break; }
    done
fi
[ -d /data/adb/ap ] && ENGINE="$ENGINE, apatch-present"
echo "kpm engine: $ENGINE"
echo "boot load result: $(cat "$MODDIR/logs/boot.log" 2>/dev/null || echo unknown)"
KPMLOADED=0
ksud kpm list 2>/dev/null | grep -qi hidhide && KPMLOADED=1
for p in /data/adb/modules/*/bin/kpatch /data/adb/ap/bin/kpatch; do
    [ -x "$p" ] && $p kpm list 2>/dev/null | grep -qi hidhide && KPMLOADED=1
done
[ "$KPMLOADED" = "1" ] && echo "kpm: LOADED" || echo "kpm: not loaded"
lsmod 2>/dev/null | grep -q '^hidhide' && echo "lkm: LOADED"
echo
echo "--- effective config ---"
if [ "$AUTO" = "1" ]; then
    echo "mode: AUTO (built-in HID capability matcher)  fake_name: $NAME  fake_phys: $PHYS"
else
    echo "mode: explicit $VID:$PID  fake_name: $NAME  fake_phys: $PHYS"
fi
echo
echo "--- kernel log (relevant lines) ---"
dmesg 2>/dev/null | grep -iE "hidhide|\[hh\]" | tail -20
echo
echo "--- input devices (/proc/bus/input/devices) ---"
echo "$DEVS"
echo
echo "--- verdict ---"
echo "$VERDICT"
} > "$OUT" 2>&1

chmod 644 "$OUT" 2>/dev/null
if [ -n "$OUTDIR" ]; then
    cp "$OUT" "$OUTDIR/" 2>/dev/null
    chmod 644 "$OUTDIR/device-diag-$TS.txt" 2>/dev/null
    # make it visible to MTP / file managers
    am broadcast -a android.intent.action.MEDIA_SCANNER_SCAN_FILE \
       -d "file://$OUTDIR/device-diag-$TS.txt" >/dev/null 2>&1
    PUBLIC_PATH=$OUTDIR/device-diag-$TS.txt
else
    echo "(shared storage unavailable - screen locked? report kept in module logs)" >> "$OUT"
    PUBLIC_PATH=$OUT
fi

# keep only the newest 5 reports in each location
[ -n "$OUTDIR" ] && ls -t "$OUTDIR"/device-diag-*.txt 2>/dev/null | tail -n +6 | while read f; do rm -f "$f"; done
ls -t "$LOGDIR"/device-diag-*.txt 2>/dev/null | tail -n +6 | while read f; do rm -f "$f"; done

echo "REPORT_PATH=$PUBLIC_PATH"
echo "VERDICT=$VERDICT"
