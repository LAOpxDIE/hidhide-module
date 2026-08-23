#!/system/bin/sh
# KernelSU/Magisk install hook.
# KPM package: nothing to check (kernel-version independent).
# Legacy LKM package: either a single top-level hidhide.ko, or a ko/
# directory with one build per kernel release (auto-selected here).
KVER=$(uname -r)

if [ -f "$MODPATH/hidhide.kpm" ]; then
    ui_print "- KPM build: kernel-version independent, no match needed"
    # .ko files may still be present as fallback; keep them as-is
    return 0 2>/dev/null || true
fi

if [ -d "$MODPATH/ko" ]; then
    if [ -f "$MODPATH/ko/$KVER/hidhide.ko" ]; then
        ui_print "- Kernel $KVER: matched prebuilt module"
        cp "$MODPATH/ko/$KVER/hidhide.ko" "$MODPATH/hidhide.ko"
    else
        ui_print "! This package has no module for kernel: $KVER"
        ui_print "! Available kernels:"
        ls "$MODPATH/ko" | while read k; do ui_print "    $k"; done
        abort  "! Please build hidhide.ko against your kernel source"
    fi
    rm -rf "$MODPATH/ko"
else
    [ -f "$MODPATH/hidhide.ko" ] || abort "! Neither hidhide.kpm nor hidhide.ko in package"
    ui_print "- Single LKM build, target kernel must be: $KVER"
fi
