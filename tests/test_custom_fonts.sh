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

# Reimporting identical content updates only the display name and keeps the
# already validated content-addressed binaries in their canonical directory.
REIMPORT_TOKEN=33333333333333333333333333333333
run_import begin "$REIMPORT_TOKEN" >/dev/null
REIMPORT_DIR="$DATA/staging/$REIMPORT_TOKEN"
cp "$MODULE/assets/fonts/mikhak/regular.ttf" "$REIMPORT_DIR/regular.ttf"
cp "$MODULE/assets/fonts/mikhak/bold.ttf" "$REIMPORT_DIR/bold.ttf"
sha256sum "$REIMPORT_DIR/regular.ttf" | awk '{print $1}' >"$REIMPORT_DIR/regular.expected.sha256"
sha256sum "$REIMPORT_DIR/bold.ttf" | awk '{print $1}' >"$REIMPORT_DIR/bold.expected.sha256"
printf '%s' 'UmVuYW1lZCBQZXJzaWFuIEZvbnQ=' >"$REIMPORT_DIR/name.b64"
REIMPORT=$(run_import finish "$REIMPORT_TOKEN")
printf '%s\n' "$REIMPORT" | grep -q '^import_result=updated-existing$'
[ "$(sed -n '1p' "$CUSTOM_DIR/name.b64")" = 'UmVuYW1lZCBQZXJzaWFuIEZvbnQ=' ]
cmp "$CUSTOM_DIR/regular.ttf" "$MODULE/assets/fonts/mikhak/regular.ttf"
cmp "$CUSTOM_DIR/bold.ttf" "$MODULE/assets/fonts/mikhak/bold.ttf"

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

EXTRA_TOKEN=44444444444444444444444444444444
run_import begin "$EXTRA_TOKEN" >/dev/null
EXTRA_DIR="$DATA/staging/$EXTRA_TOKEN"
cp "$MODULE/assets/fonts/mikhak/regular.ttf" "$EXTRA_DIR/regular.ttf"
cp "$MODULE/assets/fonts/mikhak/bold.ttf" "$EXTRA_DIR/bold.ttf"
sha256sum "$EXTRA_DIR/regular.ttf" | awk '{print $1}' >"$EXTRA_DIR/regular.expected.sha256"
sha256sum "$EXTRA_DIR/bold.ttf" | awk '{print $1}' >"$EXTRA_DIR/bold.expected.sha256"
printf '%s' 'VW5zYWZlIFN0YWdl' >"$EXTRA_DIR/name.b64"
printf '%s\n' preserve >"$SANDBOX/external-stage-victim"
chmod 0644 "$SANDBOX/external-stage-victim"
ln -s "$SANDBOX/external-stage-victim" "$EXTRA_DIR/extra"
if run_import finish "$EXTRA_TOKEN" >/dev/null 2>&1; then
  echo "Import accepted an unexpected linked staging entry" >&2
  exit 1
fi
[ "$(stat -c '%a' "$SANDBOX/external-stage-victim")" = 644 ]
[ "$(sed -n '1p' "$SANDBOX/external-stage-victim")" = preserve ]
run_import cancel "$EXTRA_TOKEN" >/dev/null

# Simulate a module update replacing the entire module tree. Persistent custom
# originals remain external and preview copies are rebuilt into the new WebUI.
UPDATED="$SANDBOX/updated-module"
mkdir -p "$UPDATED/scripts" "$UPDATED/webroot"
cp "$PROJECT_DIR/scripts/lib.sh" "$PROJECT_DIR/scripts/sync-custom.sh" "$UPDATED/scripts/"
cp "$PROJECT_DIR/webroot/font-manifest.json" "$UPDATED/webroot/"
PREVIEW_LOCK_READY="$SANDBOX/preview-lock-ready"
PREVIEW_LOCK_GATE="$SANDBOX/preview-lock-gate"
mkfifo "$PREVIEW_LOCK_GATE"
(
  exec 8>>"$DATA/.preview-sync-lock"
  flock 8
  : >"$PREVIEW_LOCK_READY"
  IFS= read -r _ <"$PREVIEW_LOCK_GATE" || true
) &
PREVIEW_LOCK_HOLDER=$!
while [ ! -e "$PREVIEW_LOCK_READY" ]; do sleep 0.05; done
BUSY_RESULT=$(PFS_MODULE_DIR="$UPDATED" PFS_DATA_DIR="$DATA" sh "$UPDATED/scripts/sync-custom.sh")
printf '%s\n' "$BUSY_RESULT" | grep -q '^status=warning$'
printf '%s\n' "$BUSY_RESULT" | grep -q '^code=preview-sync-busy$'
printf '%s\n' release >"$PREVIEW_LOCK_GATE"
wait "$PREVIEW_LOCK_HOLDER"
rm -f "$PREVIEW_LOCK_READY" "$PREVIEW_LOCK_GATE"
PFS_MODULE_DIR="$UPDATED" PFS_DATA_DIR="$DATA" sh "$UPDATED/scripts/sync-custom.sh" >/dev/null
cmp "$CUSTOM_DIR/regular.ttf" "$UPDATED/webroot/custom-fonts/$CUSTOM_ID/regular.ttf"
cmp "$CUSTOM_DIR/bold.ttf" "$UPDATED/webroot/custom-fonts/$CUSTOM_ID/bold.ttf"

# Fixed preview transaction paths bound crash residue to one copy and are
# recovered before the next synchronization.
mv "$UPDATED/webroot/custom-fonts" "$UPDATED/.custom-preview-backup"
mkdir "$UPDATED/.custom-preview-stage"
printf '%s\n' interrupted >"$UPDATED/.custom-preview-stage/residue"
PFS_MODULE_DIR="$UPDATED" PFS_DATA_DIR="$DATA" sh "$UPDATED/scripts/sync-custom.sh" >/dev/null
[ ! -e "$UPDATED/.custom-preview-stage" ]
[ ! -e "$UPDATED/.custom-preview-backup" ]
cmp "$CUSTOM_DIR/regular.ttf" "$UPDATED/webroot/custom-fonts/$CUSTOM_ID/regular.ttf"

# Staging leases remove only old, strictly named current-format import directories.
OLD_TOKEN=11111111111111111111111111111111
NEW_TOKEN=22222222222222222222222222222222
run_import begin "$OLD_TOKEN" >/dev/null
printf '%s\n' 1 >"$DATA/staging/$OLD_TOKEN/created-at"
CLEAN_BEGIN=$(run_import begin "$NEW_TOKEN")
printf '%s\n' "$CLEAN_BEGIN" | grep -q '^stale_stages_cleaned=1$'
[ ! -e "$DATA/staging/$OLD_TOKEN" ]
[ -d "$DATA/staging/$NEW_TOKEN" ]
run_import cancel "$NEW_TOKEN" >/dev/null

# A dangling persistent-root symlink must not be followed to create a new
# external staging tree.
DANGLING_TARGET="$SANDBOX/dangling-import-target"
DANGLING_DATA="$SANDBOX/dangling-import-data"
ln -s "$DANGLING_TARGET" "$DANGLING_DATA"
if PFS_MODULE_DIR="$MODULE" PFS_DATA_DIR="$DANGLING_DATA" \
  sh "$MODULE/scripts/import-font.sh" begin 55555555555555555555555555555555 >/dev/null 2>&1; then
  echo "Import followed a dangling persistent-root symlink" >&2
  exit 1
fi
[ ! -e "$DANGLING_TARGET" ]

# Deletion is allowlisted, refuses the selected family, and removes both the
# persistent registry entry and its module-local preview after switching away.
if PFS_MODULE_DIR="$MODULE" PFS_DATA_DIR="$DATA" \
  sh "$MODULE/scripts/delete-custom-font.sh" "$CUSTOM_ID" >/dev/null 2>&1; then
  echo "Selected custom font was deleted" >&2
  exit 1
fi
PFS_MODULE_DIR="$MODULE" PFS_DATA_DIR="$DATA" PFS_SKIP_KSU_CONFIG=1 \
  sh "$MODULE/scripts/apply-font.sh" mikhak >/dev/null

# A symlinked persistent root must never redirect deletion into another store.
EXTERNAL_STORE="$SANDBOX/external-store"
UNSAFE_DATA="$SANDBOX/unsafe-data-link"
mkdir -p "$EXTERNAL_STORE/custom-fonts"
cp -R "$CUSTOM_DIR" "$EXTERNAL_STORE/custom-fonts/$CUSTOM_ID"
printf '%s\n' preserve >"$EXTERNAL_STORE/marker"
ln -s "$EXTERNAL_STORE" "$UNSAFE_DATA"
if PFS_MODULE_DIR="$MODULE" PFS_DATA_DIR="$UNSAFE_DATA" \
  sh "$MODULE/scripts/delete-custom-font.sh" "$CUSTOM_ID" >/dev/null 2>&1; then
  echo "Custom deletion followed a symlinked persistent root" >&2
  exit 1
fi
[ -f "$EXTERNAL_STORE/marker" ]
[ -f "$EXTERNAL_STORE/custom-fonts/$CUSTOM_ID/regular.ttf" ]

# Simulate power loss immediately after the deletion commit rename. The next
# authoritative registry read completes the durable transaction and removes no
# path outside its fixed trash location.
CRASH_DATA="$SANDBOX/crash-data"
cp -R "$DATA" "$CRASH_DATA"
printf '%s\n' "$CUSTOM_ID" >"$CRASH_DATA/.delete-transaction"
mv "$CRASH_DATA/custom-fonts/$CUSTOM_ID" "$CRASH_DATA/.deleted-custom-font"
CRASH_LIST=$(PFS_MODULE_DIR="$MODULE" PFS_DATA_DIR="$CRASH_DATA" \
  sh "$MODULE/scripts/list-custom-fonts.sh")
printf '%s\n' "$CRASH_LIST" | grep -q '^status=ok$'
if printf '%s\n' "$CRASH_LIST" | grep -q "^custom=$CUSTOM_ID|"; then
  echo "Recovered deletion still listed the removed custom font" >&2
  exit 1
fi
[ ! -e "$CRASH_DATA/.delete-transaction" ]
[ ! -e "$CRASH_DATA/.deleted-custom-font" ]
[ ! -e "$CRASH_DATA/custom-fonts/$CUSTOM_ID" ]

DELETE_RESULT=$(PFS_MODULE_DIR="$MODULE" PFS_DATA_DIR="$DATA" \
  sh "$MODULE/scripts/delete-custom-font.sh" "$CUSTOM_ID")
printf '%s\n' "$DELETE_RESULT" | grep -q '^status=ok$'
printf '%s\n' "$DELETE_RESULT" | grep -q "^removed=$CUSTOM_ID$"
[ ! -e "$CUSTOM_DIR" ]
[ ! -e "$MODULE/webroot/custom-fonts/$CUSTOM_ID" ]
if PFS_MODULE_DIR="$MODULE" PFS_DATA_DIR="$DATA" \
  sh "$MODULE/scripts/delete-custom-font.sh" '../../escape' >/dev/null 2>&1; then
  echo "Custom deletion accepted path traversal" >&2
  exit 1
fi

echo "Custom-font import and persistence tests passed"
