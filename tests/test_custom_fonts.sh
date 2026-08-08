#!/usr/bin/env sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
SANDBOX=$(mktemp -d)
trap 'rm -rf -- "$SANDBOX"' EXIT HUP INT TERM

MODULE="$SANDBOX/module"
DATA="$SANDBOX/data"
mkdir -p "$MODULE/scripts" "$MODULE/webroot" "$MODULE/state" "$MODULE/system/fonts"
cp -R "$PROJECT_DIR/assets" "$MODULE/assets"
cp "$PROJECT_DIR/scripts/"*.sh "$MODULE/scripts/"
cp "$PROJECT_DIR/webroot/font-manifest.json" "$MODULE/webroot/"
cp "$PROJECT_DIR/state/supported-targets" "$PROJECT_DIR/state/selected-font" "$MODULE/state/"
cp "$PROJECT_DIR/system/fonts/"*.ttf "$MODULE/system/fonts/"

run_import() {
  PFS_MODULE_DIR="$MODULE" PFS_DATA_DIR="$DATA" sh "$MODULE/scripts/import-font.sh" "$@"
}

TOKEN=0123456789abcdef0123456789abcdef
BEGIN=$(run_import begin "$TOKEN")
printf '%s\n' "$BEGIN" | grep -q '^status=ok$'
IMPORT_DIR="$DATA/staging/$TOKEN"
cp "$MODULE/assets/fonts/mikhak/regular.ttf" "$IMPORT_DIR/regular.ttf"
cp "$MODULE/assets/fonts/mikhak/bold.ttf" "$IMPORT_DIR/bold.ttf"
sha256sum "$IMPORT_DIR/regular.ttf" | awk '{print $1}' >"$IMPORT_DIR/regular.expected.sha256"
sha256sum "$IMPORT_DIR/bold.ttf" | awk '{print $1}' >"$IMPORT_DIR/bold.expected.sha256"
printf '%s' 'TXkgUGVyc2lhbiBGb250' >"$IMPORT_DIR/name.b64"
FINISH=$(run_import finish "$TOKEN")
printf '%s\n' "$FINISH" | grep -q '^status=ok$'
CUSTOM_ID=$(printf '%s\n' "$FINISH" | sed -n 's/^id=//p')
case "$CUSTOM_ID" in custom-[0-9a-f]*) ;; *) echo "Unsafe custom ID" >&2; exit 1 ;; esac

CUSTOM_DIR="$DATA/custom-fonts/$CUSTOM_ID"
[ -f "$CUSTOM_DIR/regular.ttf" ]
[ -f "$CUSTOM_DIR/bold.ttf" ]
[ "$(stat -c '%a' "$CUSTOM_DIR")" = 700 ]
[ "$(stat -c '%a' "$CUSTOM_DIR/regular.ttf")" = 600 ]
cmp "$CUSTOM_DIR/regular.ttf" "$MODULE/webroot/custom-fonts/$CUSTOM_ID/regular.ttf"
cmp "$CUSTOM_DIR/bold.ttf" "$MODULE/webroot/custom-fonts/$CUSTOM_ID/bold.ttf"

LIST=$(PFS_MODULE_DIR="$MODULE" PFS_DATA_DIR="$DATA" sh "$MODULE/scripts/list-custom-fonts.sh")
printf '%s\n' "$LIST" | grep -q "^custom=$CUSTOM_ID|TXkgUGVyc2lhbiBGb250|"

PFS_MODULE_DIR="$MODULE" PFS_DATA_DIR="$DATA" PFS_SKIP_KSU_CONFIG=1 \
  sh "$MODULE/scripts/apply-font.sh" "$CUSTOM_ID" | grep -q '^status=ok$'
cmp "$CUSTOM_DIR/regular.ttf" "$MODULE/system/fonts/NotoNaskhArabicUI-Regular.ttf"
cmp "$CUSTOM_DIR/regular.ttf" "$MODULE/system/fonts/NotoNaskhArabic-Regular.ttf"
cmp "$CUSTOM_DIR/bold.ttf" "$MODULE/system/fonts/NotoNaskhArabicUI-Bold.ttf"
cmp "$CUSTOM_DIR/bold.ttf" "$MODULE/system/fonts/NotoNaskhArabic-Bold.ttf"

if run_import begin '../../escape' >/dev/null 2>&1; then
  echo "Import accepted a path traversal token" >&2
  exit 1
fi

BAD_TOKEN=abcdef0123456789abcdef0123456789
run_import begin "$BAD_TOKEN" >/dev/null
BAD_DIR="$DATA/staging/$BAD_TOKEN"
dd if=/dev/zero of="$BAD_DIR/regular.ttf" bs=512 count=1 status=none
cp "$MODULE/assets/fonts/mikhak/bold.ttf" "$BAD_DIR/bold.ttf"
sha256sum "$BAD_DIR/regular.ttf" | awk '{print $1}' >"$BAD_DIR/regular.expected.sha256"
sha256sum "$BAD_DIR/bold.ttf" | awk '{print $1}' >"$BAD_DIR/bold.expected.sha256"
printf '%s' 'QmFkIEZvbnQ=' >"$BAD_DIR/name.b64"
if run_import finish "$BAD_TOKEN" >/dev/null 2>&1; then
  echo "Import accepted a corrupt Regular file" >&2
  exit 1
fi

MISMATCH_TOKEN=fedcba9876543210fedcba9876543210
run_import begin "$MISMATCH_TOKEN" >/dev/null
MISMATCH_DIR="$DATA/staging/$MISMATCH_TOKEN"
cp "$MODULE/assets/fonts/mikhak/regular.ttf" "$MISMATCH_DIR/regular.ttf"
cp "$MODULE/assets/fonts/mikhak/bold.ttf" "$MISMATCH_DIR/bold.ttf"
printf '%064d\n' 0 >"$MISMATCH_DIR/regular.expected.sha256"
sha256sum "$MISMATCH_DIR/bold.ttf" | awk '{print $1}' >"$MISMATCH_DIR/bold.expected.sha256"
printf '%s' 'VHJhbnNmZXIgTWlzbWF0Y2g=' >"$MISMATCH_DIR/name.b64"
if run_import finish "$MISMATCH_TOKEN" >/dev/null 2>&1; then
  echo "Import accepted a transfer checksum mismatch" >&2
  exit 1
fi

# Simulate a module update replacing the entire module tree. Persistent custom
# originals remain external and preview copies are rebuilt into the new WebUI.
UPDATED="$SANDBOX/updated-module"
mkdir -p "$UPDATED/scripts" "$UPDATED/webroot"
cp "$PROJECT_DIR/scripts/lib.sh" "$PROJECT_DIR/scripts/sync-custom.sh" "$UPDATED/scripts/"
cp "$PROJECT_DIR/webroot/font-manifest.json" "$UPDATED/webroot/"
mkdir "$DATA/.preview-sync-lock"
printf '%s\n' "$$" >"$DATA/.preview-sync-lock/pid"
BUSY_RESULT=$(PFS_MODULE_DIR="$UPDATED" PFS_DATA_DIR="$DATA" sh "$UPDATED/scripts/sync-custom.sh")
printf '%s\n' "$BUSY_RESULT" | grep -q '^status=warning$'
printf '%s\n' "$BUSY_RESULT" | grep -q '^code=preview-sync-busy$'
rm "$DATA/.preview-sync-lock/pid"
rmdir "$DATA/.preview-sync-lock"
PFS_MODULE_DIR="$UPDATED" PFS_DATA_DIR="$DATA" sh "$UPDATED/scripts/sync-custom.sh" >/dev/null
cmp "$CUSTOM_DIR/regular.ttf" "$UPDATED/webroot/custom-fonts/$CUSTOM_ID/regular.ttf"
cmp "$CUSTOM_DIR/bold.ttf" "$UPDATED/webroot/custom-fonts/$CUSTOM_ID/bold.ttf"

echo "Custom-font import and persistence tests passed"
