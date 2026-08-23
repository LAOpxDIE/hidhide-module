#!/usr/bin/env bash
# Build a KernelSU/Magisk/APatch-compatible module archive from local outputs.
set -euo pipefail

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
OUTDIR=${OUTDIR:-"$ROOT/dist"}
MULTI=0

case "${1:-}" in
  "") ;;
  --multi) MULTI=1 ;;
  *) echo "Usage: $0 [--multi]" >&2; exit 2 ;;
esac

KPM="$ROOT/kpm/hidhide.kpm"
KO="$ROOT/hidhide.ko"
HAS_KPM=0
HAS_KO=0
[ -f "$KPM" ] && HAS_KPM=1
[ -f "$KO" ] && HAS_KO=1

if [ "$MULTI" = "1" ]; then
  [ -d "$ROOT/ko" ] || { echo "ko/ not found" >&2; exit 1; }
  HAS_KO=1
fi

if [ "$HAS_KPM" = "0" ] && [ "$HAS_KO" = "0" ]; then
  echo "Nothing to pack: build kpm/hidhide.kpm or hidhide.ko first" >&2
  exit 1
fi

TMPROOT=$(mktemp -d "${TMPDIR:-/tmp}/hidhide-pack.XXXXXX")
trap 'rm -rf -- "$TMPROOT"' EXIT
PKG="$TMPROOT/pkg"
mkdir -p "$PKG" "$OUTDIR"

cp "$ROOT/module.prop" "$ROOT/post-fs-data.sh" "$ROOT/service.sh" \
   "$ROOT/collect.sh" "$ROOT/load.sh" "$ROOT/customize.sh" "$PKG/"
[ "$HAS_KPM" = "1" ] && cp "$KPM" "$PKG/hidhide.kpm"

if [ "$MULTI" = "1" ]; then
  cp -R "$ROOT/ko" "$PKG/"
elif [ "$HAS_KO" = "1" ]; then
  cp "$KO" "$PKG/"
fi

cp -R "$ROOT/webroot" "$PKG/"
chmod 644 "$PKG/module.prop"
find "$PKG" \( -name '*.ko' -o -name '*.kpm' \) -exec chmod 644 {} +
chmod 755 "$PKG/post-fs-data.sh" "$PKG/service.sh" "$PKG/collect.sh" \
          "$PKG/load.sh" "$PKG/customize.sh"

ARCHIVE="$OUTDIR/HIDHide-KSU.zip"
rm -f -- "$ARCHIVE" "$ARCHIVE.sha256"
(
  cd "$PKG"
  zip -qr "$ARCHIVE" .
)
(
  cd "$OUTDIR"
  sha256sum "$(basename "$ARCHIVE")" > "$(basename "$ARCHIVE").sha256"
)

echo "Created: $ARCHIVE"
echo "SHA-256: $ARCHIVE.sha256"
