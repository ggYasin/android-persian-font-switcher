#!/usr/bin/env sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
OUTPUT=${1:-"$PROJECT_DIR/Vazirmatn-Persian-Fallback-v33.003.zip"}
STAGE=$(mktemp -d)
trap 'rm -rf -- "$STAGE"' EXIT HUP INT TERM

mkdir -p "$STAGE/system/fonts"
cp "$PROJECT_DIR/module.prop" "$STAGE/module.prop"
cp "$PROJECT_DIR/customize.sh" "$STAGE/customize.sh"
cp "$PROJECT_DIR/system/fonts/NotoNaskhArabicUI-Regular.ttf" "$STAGE/system/fonts/NotoNaskhArabicUI-Regular.ttf"
cp "$PROJECT_DIR/system/fonts/NotoNaskhArabicUI-Bold.ttf" "$STAGE/system/fonts/NotoNaskhArabicUI-Bold.ttf"
cp "$PROJECT_DIR/system/fonts/NotoNaskhArabic-Regular.ttf" "$STAGE/system/fonts/NotoNaskhArabic-Regular.ttf"
cp "$PROJECT_DIR/system/fonts/NotoNaskhArabic-Bold.ttf" "$STAGE/system/fonts/NotoNaskhArabic-Bold.ttf"

chmod 0644 "$STAGE/module.prop" "$STAGE/system/fonts/"*.ttf
chmod 0755 "$STAGE/customize.sh"
touch -t 202401010000 "$STAGE/module.prop" "$STAGE/customize.sh" "$STAGE/system/fonts/"*.ttf

rm -f -- "$OUTPUT"
(
  cd "$STAGE"
  zip -X -9 "$OUTPUT" \
    module.prop \
    customize.sh \
    system/fonts/NotoNaskhArabicUI-Regular.ttf \
    system/fonts/NotoNaskhArabicUI-Bold.ttf \
    system/fonts/NotoNaskhArabic-Regular.ttf \
    system/fonts/NotoNaskhArabic-Bold.ttf
)

sha256sum "$OUTPUT"
