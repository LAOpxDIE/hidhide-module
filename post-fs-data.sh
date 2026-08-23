#!/system/bin/sh
# KernelSU/Magisk/APatch module script: load hidhide as early as possible
# via the universal dispatcher (auto-detects ksud kpm / kpatch / legacy LKM).
MODDIR=${0%/*}
mkdir -p "$MODDIR/logs"
sh "$MODDIR/load.sh" > "$MODDIR/logs/boot.log" 2>&1
