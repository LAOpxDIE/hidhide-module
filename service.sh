#!/system/bin/sh
# HIDHide boot service:
#   1. retry the KPM load if the engine was not ready at post-fs-data
#   2. recover "plugged at boot" devices: USB enumeration happens before
#      the hook is installed, so a touchscreen left plugged across a
#      reboot stays undisguised. Detect such stale USB touch devices and
#      re-enumerate them (authorized 0/1) so the hook patches them.
#   3. write an automatic diagnostic report (see collect.sh).
MODDIR=${0%/*}

# engine ordering safety net: if the boot-time (post-fs-data) load ran
# before the KPM engine was up (KPatch-Next may activate at service
# stage), retry once here. load.sh exits immediately if already loaded.
sh "$MODDIR/load.sh" >> "$MODDIR/logs/boot.log" 2>&1

until [ "$(getprop sys.boot_completed)" = "1" ]; do sleep 5; done
sleep 20

# ---- stale USB touchscreen recovery ----
# /proc/bus/input/devices prints bitmaps as space-separated 64-bit words,
# HIGH word first, leading zeros stripped per word, e.g. "400 0 0 0 0 0".
#   BTN_TOUCH   = keybit 330 -> word 5 (6th token from right), bit 10
#                 -> 3rd hex digit from right of that word, mask 0x4
#   ABS_MT_SLOT = absbit 47  -> word 0 (last token), bit 47
#                 -> 12th hex digit from right of that word, mask 0x8
fix_stale_usb_touch() {
    cat /proc/bus/input/devices 2>/dev/null | awk '
        function hexval(c,   v) {
            v = index("0123456789abcdef", c)
            if (v == 0) v = index("0123456789ABCDEF", c)
            return v - 1
        }
        BEGIN { RS="" }
        /Bus=0003/ {
            key=""; abs=""; sys=""
            n=split($0, L, "\n")
            for (i=1; i<=n; i++) {
                if (L[i] ~ /^B: KEY=/)  key=substr(L[i], 8)
                if (L[i] ~ /^B: ABS=/)  abs=substr(L[i], 8)
                if (L[i] ~ /^S: Sysfs=/) sys=substr(L[i], 10)
            }
            if (sys == "") next
            nk = split(key, K, " ")
            na = split(abs, A, " ")
            if (nk < 6 || na < 1) next
            kw = K[nk - 5]              # keybit word 5 (bits 320-383)
            aw = A[na]                  # absbit word 0 (bits 0-63)
            kp = length(kw) - 2         # bit 10 -> 3rd hex digit from right
            ap = length(aw) - 11        # bit 47 -> 12th hex digit from right
            if (kp < 1 || ap < 1) next
            kv = hexval(substr(kw, kp, 1))
            av = hexval(substr(aw, ap, 1))
            if (kv >= 0 && int(kv / 4) % 2 == 1 && av >= 8)
                print sys
        }' | while read -r sp; do
            dev=$(echo "$sp" | grep -oE 'usb[0-9]+/[0-9]+-[0-9.]+/' | head -1 | cut -d/ -f2)
            [ -n "$dev" ] && [ -w "/sys/bus/usb/devices/$dev/authorized" ] || continue
            echo 0 > "/sys/bus/usb/devices/$dev/authorized" 2>/dev/null
            sleep 1
            echo 1 > "/sys/bus/usb/devices/$dev/authorized" 2>/dev/null
            echo "re-enumerated stale usb touch: $dev" >> "$MODDIR/logs/boot.log"
        done
}

fix_stale_usb_touch
sleep 25

sh "$MODDIR/collect.sh" >/dev/null 2>&1

# keep only the newest 5 reports in module storage
ls -t "$MODDIR"/logs/device-diag-*.txt 2>/dev/null | tail -n +6 | while read f; do rm -f "$f"; done
