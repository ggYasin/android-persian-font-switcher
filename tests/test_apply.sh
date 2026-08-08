#!/usr/bin/env sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
SANDBOX=$(mktemp -d)
trap 'rm -rf -- "$SANDBOX"' EXIT HUP INT TERM

mkdir -p "$SANDBOX/scripts" "$SANDBOX/webroot" "$SANDBOX/state" "$SANDBOX/system/fonts"
cp -R "$PROJECT_DIR/assets" "$SANDBOX/assets"
cp "$PROJECT_DIR/scripts/apply-font.sh" "$PROJECT_DIR/scripts/get-status.sh" "$PROJECT_DIR/scripts/lib.sh" "$SANDBOX/scripts/"
cp "$PROJECT_DIR/webroot/font-manifest.json" "$SANDBOX/webroot/"
cp "$PROJECT_DIR/state/supported-targets" "$PROJECT_DIR/state/selected-font" "$SANDBOX/state/"
cp "$PROJECT_DIR/system/fonts/"*.ttf "$SANDBOX/system/fonts/"

apply() {
  PFS_MODULE_DIR="$SANDBOX" PFS_SKIP_KSU_CONFIG=1 sh "$SANDBOX/scripts/apply-font.sh" "$1"
}

assert_mapping() {
  FONT_ID="$1"
  cmp "$SANDBOX/assets/fonts/$FONT_ID/regular.ttf" "$SANDBOX/system/fonts/NotoNaskhArabicUI-Regular.ttf"
  cmp "$SANDBOX/assets/fonts/$FONT_ID/regular.ttf" "$SANDBOX/system/fonts/NotoNaskhArabic-Regular.ttf"
  cmp "$SANDBOX/assets/fonts/$FONT_ID/bold.ttf" "$SANDBOX/system/fonts/NotoNaskhArabicUI-Bold.ttf"
  cmp "$SANDBOX/assets/fonts/$FONT_ID/bold.ttf" "$SANDBOX/system/fonts/NotoNaskhArabic-Bold.ttf"
  [ ! -e "$SANDBOX/skip_mount" ]
}

for FONT_ID in vazirmatn estedad sahel; do
  apply "$FONT_ID" | grep -q '^status=ok$'
  assert_mapping "$FONT_ID"
done

BEFORE=$(sha256sum "$SANDBOX/system/fonts/"*.ttf)
if apply '../../escape' >/dev/null 2>&1; then
  echo "Path traversal ID was accepted" >&2
  exit 1
fi
if apply 'sahel;touch-pwned' >/dev/null 2>&1; then
  echo "Shell metacharacter ID was accepted" >&2
  exit 1
fi
[ "$BEFORE" = "$(sha256sum "$SANDBOX/system/fonts/"*.ttf)" ]

mkdir "$SANDBOX/.apply-lock"
if apply vazirmatn >/dev/null 2>&1; then
  echo "Concurrent apply lock was ignored" >&2
  exit 1
fi
rmdir "$SANDBOX/.apply-lock"

apply system-default | grep -q '^status=ok$'
[ -e "$SANDBOX/skip_mount" ]
[ ! -d "$SANDBOX/system/fonts" ]
[ "$(sed -n '1p' "$SANDBOX/state/selected-font")" = "system-default" ]

apply estedad | grep -q '^status=ok$'
assert_mapping estedad

printf '%s\n' invalid-target.ttf >"$SANDBOX/state/supported-targets"
if apply vazirmatn >/dev/null 2>&1; then
  echo "Invalid target allowlist was accepted" >&2
  exit 1
fi
cp "$PROJECT_DIR/state/supported-targets" "$SANDBOX/state/supported-targets"

printf '%s' broken >"$SANDBOX/assets/fonts/sahel/regular.ttf"
if apply sahel >/dev/null 2>&1; then
  echo "Corrupt font asset was accepted" >&2
  exit 1
fi
[ -e "$SANDBOX/skip_mount" ]

STATUS=$(PFS_MODULE_DIR="$SANDBOX" sh "$SANDBOX/scripts/get-status.sh")
printf '%s\n' "$STATUS" | grep -q '^selected=system-default$'
printf '%s\n' "$STATUS" | grep -q '^layout=valid$'

echo "Apply-script tests passed"
