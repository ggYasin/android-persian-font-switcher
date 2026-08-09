#!/usr/bin/env sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
SANDBOX=$(mktemp -d)
trap 'rm -rf -- "$SANDBOX"' EXIT HUP INT TERM

mkdir -p "$SANDBOX/bin" "$SANDBOX/scripts" "$SANDBOX/webroot" "$SANDBOX/state" "$SANDBOX/system/fonts" "$SANDBOX/effective" "$SANDBOX/adb/modules"
cp -R "$PROJECT_DIR/assets" "$SANDBOX/assets"
cp "$PROJECT_DIR/scripts/apply-font.sh" "$PROJECT_DIR/scripts/get-status.sh" "$PROJECT_DIR/scripts/lib.sh" "$SANDBOX/scripts/"
cp "$PROJECT_DIR/webroot/font-manifest.json" "$SANDBOX/webroot/"
cp "$PROJECT_DIR/state/supported-targets" "$PROJECT_DIR/state/selected-font" "$SANDBOX/state/"
cp "$PROJECT_DIR/system/fonts/"*.ttf "$SANDBOX/system/fonts/"
cp "$PROJECT_DIR/system/fonts/"*.ttf "$SANDBOX/effective/"
printf '%s\n' '#!/usr/bin/env sh' 'exit 0' >"$SANDBOX/bin/sync"
chmod 0755 "$SANDBOX/bin/sync"

apply() {
  PFS_MODULE_DIR="$SANDBOX" PFS_SKIP_KSU_CONFIG=1 PATH="$SANDBOX/bin:$PATH" \
    sh "$SANDBOX/scripts/apply-font.sh" "$1"
}

assert_mapping() {
  FONT_ID="$1"
  cmp "$SANDBOX/assets/fonts/$FONT_ID/regular.ttf" "$SANDBOX/system/fonts/NotoNaskhArabicUI-Regular.ttf"
  cmp "$SANDBOX/assets/fonts/$FONT_ID/regular.ttf" "$SANDBOX/system/fonts/NotoNaskhArabic-Regular.ttf"
  cmp "$SANDBOX/assets/fonts/$FONT_ID/bold.ttf" "$SANDBOX/system/fonts/NotoNaskhArabicUI-Bold.ttf"
  cmp "$SANDBOX/assets/fonts/$FONT_ID/bold.ttf" "$SANDBOX/system/fonts/NotoNaskhArabic-Bold.ttf"
  [ ! -e "$SANDBOX/skip_mount" ]
}

for FONT_ID in $(sed -n 's/.*"id": "\([a-z0-9_-]*\)".*/\1/p' "$PROJECT_DIR/webroot/font-manifest.json"); do
  [ "$FONT_ID" = system-default ] && continue
  apply "$FONT_ID" | grep -q '^status=ok$'
  assert_mapping "$FONT_ID"
done

# Effective mounted hashes, not saved config, determine active vs pending.
apply vazirmatn >/dev/null
cp "$SANDBOX/system/fonts/"*.ttf "$SANDBOX/effective/"
STATUS=$(PFS_MODULE_DIR="$SANDBOX" PFS_DATA_DIR="$SANDBOX/data" PFS_ADB_ROOT="$SANDBOX/adb" \
  PFS_EFFECTIVE_FONT_DIR="$SANDBOX/effective" sh "$SANDBOX/scripts/get-status.sh")
printf '%s\n' "$STATUS" | grep -q '^active=vazirmatn$'
printf '%s\n' "$STATUS" | grep -q '^selected=vazirmatn$'
printf '%s\n' "$STATUS" | grep -q '^restart_required=false$'
printf '%s\n' "$STATUS" | grep -q '^fontloader=not-detected$'

apply estedad >/dev/null
STATUS=$(PFS_MODULE_DIR="$SANDBOX" PFS_DATA_DIR="$SANDBOX/data" PFS_ADB_ROOT="$SANDBOX/adb" \
  PFS_EFFECTIVE_FONT_DIR="$SANDBOX/effective" sh "$SANDBOX/scripts/get-status.sh")
printf '%s\n' "$STATUS" | grep -q '^active=vazirmatn$'
printf '%s\n' "$STATUS" | grep -q '^selected=estedad$'
printf '%s\n' "$STATUS" | grep -q '^restart_required=true$'

cp "$SANDBOX/system/fonts/"*.ttf "$SANDBOX/effective/"
STATUS=$(PFS_MODULE_DIR="$SANDBOX" PFS_DATA_DIR="$SANDBOX/data" PFS_ADB_ROOT="$SANDBOX/adb" \
  PFS_EFFECTIVE_FONT_DIR="$SANDBOX/effective" sh "$SANDBOX/scripts/get-status.sh")
printf '%s\n' "$STATUS" | grep -q '^active=estedad$'
printf '%s\n' "$STATUS" | grep -q '^restart_required=false$'

mkdir -p "$SANDBOX/adb/modules/fontloader"
printf '%s\n' 'id=fontloader' >"$SANDBOX/adb/modules/fontloader/module.prop"
STATUS=$(PFS_MODULE_DIR="$SANDBOX" PFS_DATA_DIR="$SANDBOX/data" PFS_ADB_ROOT="$SANDBOX/adb" \
  PFS_EFFECTIVE_FONT_DIR="$SANDBOX/effective" sh "$SANDBOX/scripts/get-status.sh")
printf '%s\n' "$STATUS" | grep -q '^fontloader=enabled$'
: >"$SANDBOX/adb/modules/fontloader/disable"
STATUS=$(PFS_MODULE_DIR="$SANDBOX" PFS_DATA_DIR="$SANDBOX/data" PFS_ADB_ROOT="$SANDBOX/adb" \
  PFS_EFFECTIVE_FONT_DIR="$SANDBOX/effective" sh "$SANDBOX/scripts/get-status.sh")
printf '%s\n' "$STATUS" | grep -q '^fontloader=disabled$'
rm -f "$SANDBOX/adb/modules/fontloader/disable"
: >"$SANDBOX/adb/modules/fontloader/remove"
STATUS=$(PFS_MODULE_DIR="$SANDBOX" PFS_DATA_DIR="$SANDBOX/data" PFS_ADB_ROOT="$SANDBOX/adb" \
  PFS_EFFECTIVE_FONT_DIR="$SANDBOX/effective" sh "$SANDBOX/scripts/get-status.sh")
printf '%s\n' "$STATUS" | grep -q '^fontloader=pending-removal$'
rm -rf "$SANDBOX/adb/modules/fontloader"
mkdir -p "$SANDBOX/adb/modules_update/fontloader"
printf '%s\n' 'id=fontloader' >"$SANDBOX/adb/modules_update/fontloader/module.prop"
STATUS=$(PFS_MODULE_DIR="$SANDBOX" PFS_DATA_DIR="$SANDBOX/data" PFS_ADB_ROOT="$SANDBOX/adb" \
  PFS_EFFECTIVE_FONT_DIR="$SANDBOX/effective" sh "$SANDBOX/scripts/get-status.sh")
printf '%s\n' "$STATUS" | grep -q '^fontloader=pending-install$'
mkdir -p "$SANDBOX/adb/modules/fontloader"
printf '%s\n' 'id=fontloader' >"$SANDBOX/adb/modules/fontloader/module.prop"
STATUS=$(PFS_MODULE_DIR="$SANDBOX" PFS_DATA_DIR="$SANDBOX/data" PFS_ADB_ROOT="$SANDBOX/adb" \
  PFS_EFFECTIVE_FONT_DIR="$SANDBOX/effective" sh "$SANDBOX/scripts/get-status.sh")
printf '%s\n' "$STATUS" | grep -q '^fontloader=pending-install-or-update$'

# A stale KernelSU config must not override the module state committed with the
# current overlay when a best-effort config update previously failed.
mkdir -p "$SANDBOX/adb/ksu/bin"
printf '%s\n' '#!/usr/bin/env sh' 'printf "%s\n" vazirmatn' >"$SANDBOX/adb/ksu/bin/ksud"
chmod 0755 "$SANDBOX/adb/ksu/bin/ksud"
STATE_SELECTION=$(PFS_MODULE_DIR="$SANDBOX" PFS_ADB_ROOT="$SANDBOX/adb" \
  sh -c '. "$1"; pfs_read_selection' sh "$SANDBOX/scripts/lib.sh")
[ "$STATE_SELECTION" = estedad ]

printf '%s\n' '#!/usr/bin/env sh' 'exit 1' >"$SANDBOX/failing-nsenter"
chmod 0755 "$SANDBOX/failing-nsenter"
STATUS=$(PFS_MODULE_DIR="$SANDBOX" PFS_DATA_DIR="$SANDBOX/data" PFS_ADB_ROOT="$SANDBOX/adb" \
  PFS_NSENTER_BIN="$SANDBOX/failing-nsenter" sh "$SANDBOX/scripts/get-status.sh")
printf '%s\n' "$STATUS" | grep -q '^active=unknown$'
printf '%s\n' "$STATUS" | grep -q '^active_scope=unavailable$'

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

# The retained regular lock file is advisory; a live kernel-held flock blocks a
# second operation and is released automatically even if the holder is killed.
LOCK_READY="$SANDBOX/lock-ready"
LOCK_GATE="$SANDBOX/lock-gate"
mkfifo "$LOCK_GATE"
(
  exec 8>>"$SANDBOX/.apply-lock"
  flock 8
  : >"$LOCK_READY"
  IFS= read -r _ <"$LOCK_GATE" || true
) &
LOCK_HOLDER=$!
while [ ! -e "$LOCK_READY" ]; do sleep 0.05; done
if apply vazirmatn >/dev/null 2>&1; then
  echo "Concurrent apply lock was ignored" >&2
  exit 1
fi
printf '%s\n' release >"$LOCK_GATE"
wait "$LOCK_HOLDER"
rm -f "$LOCK_READY" "$LOCK_GATE"

CRASH_LOCK_READY="$SANDBOX/crash-lock-ready"
CRASH_LOCK_GATE="$SANDBOX/crash-lock-gate"
mkfifo "$CRASH_LOCK_GATE"
(
  exec 8>>"$SANDBOX/.apply-lock"
  flock 8
  : >"$CRASH_LOCK_READY"
  IFS= read -r _ <"$CRASH_LOCK_GATE" || true
) &
CRASH_LOCK_HOLDER=$!
while [ ! -e "$CRASH_LOCK_READY" ]; do sleep 0.05; done
kill -KILL "$CRASH_LOCK_HOLDER"
wait "$CRASH_LOCK_HOLDER" 2>/dev/null || true
apply vazirmatn | grep -q '^status=ok$'
rm -f "$CRASH_LOCK_READY" "$CRASH_LOCK_GATE"

# A non-regular lock path is an explicit capability error, never misreported as
# another live operation and never followed outside the module directory.
rm -f "$SANDBOX/.apply-lock"
printf '%s\n' preserve >"$SANDBOX/external-lock-target"
ln -s "$SANDBOX/external-lock-target" "$SANDBOX/.apply-lock"
UNSAFE_LOCK_RESULT=$(apply vazirmatn 2>&1 || true)
printf '%s\n' "$UNSAFE_LOCK_RESULT" | grep -q '^code=lock-unavailable$'
[ "$(sed -n '1p' "$SANDBOX/external-lock-target")" = preserve ]
rm -f "$SANDBOX/.apply-lock"

# An owner-identified dead directory lock from an older release is migrated to
# the crash-safe retained flock file.
rm -f "$SANDBOX/.apply-lock"
mkdir "$SANDBOX/.apply-lock"
printf '%s\n' 99999999 >"$SANDBOX/.apply-lock/pid"
STALE_RESULT=$(apply vazirmatn)
printf '%s\n' "$STALE_RESULT" | grep -q '^status=ok$'
printf '%s\n' "$STALE_RESULT" | grep -q '^recovered_stale_lock=1$'
[ -f "$SANDBOX/.apply-lock" ]

# If the old overlay rename fails, cleanup must leave all four working files in
# place instead of confusing them with a newly installed overlay.
apply estedad >/dev/null
BEFORE_BACKUP_FAILURE=$(sha256sum "$SANDBOX/system/fonts/"*.ttf)
MV_SHIM_DIR="$SANDBOX/mv-shim"
mkdir "$MV_SHIM_DIR"
REAL_MV=$(command -v mv)
printf '%s\n' \
  '#!/usr/bin/env sh' \
  'if [ "$#" -eq 2 ] && [ "$1" = "$PFS_FAIL_SOURCE" ] && [ "$2" = "$PFS_FAIL_TARGET" ]; then exit 70; fi' \
  'exec "$PFS_REAL_MV" "$@"' >"$MV_SHIM_DIR/mv"
chmod 0755 "$MV_SHIM_DIR/mv"
BACKUP_FAILURE=$(PFS_MODULE_DIR="$SANDBOX" PFS_SKIP_KSU_CONFIG=1 \
  PFS_FAIL_SOURCE="$SANDBOX/system/fonts" PFS_FAIL_TARGET="$SANDBOX/.font-backup" \
  PFS_REAL_MV="$REAL_MV" PATH="$MV_SHIM_DIR:$PATH" \
  sh "$SANDBOX/scripts/apply-font.sh" vazirmatn 2>&1 || true)
printf '%s\n' "$BACKUP_FAILURE" | grep -q '^code=overlay-backup-failed$'
[ "$BEFORE_BACKUP_FAILURE" = "$(sha256sum "$SANDBOX/system/fonts/"*.ttf)" ]
[ -e "$SANDBOX/skip_mount" ]
[ ! -e "$SANDBOX/.font-transaction" ]
rm -f "$SANDBOX/skip_mount"

# The fail-safe marker must cross a storage barrier before the working overlay
# is moved. A failed barrier returns a distinct error and changes no font file.
apply estedad >/dev/null
BEFORE_BARRIER_FAILURE=$(sha256sum "$SANDBOX/system/fonts/"*.ttf)
printf '%s\n' '#!/usr/bin/env sh' 'exit 70' >"$SANDBOX/bin/sync"
BARRIER_FAILURE=$(apply vazirmatn 2>&1 || true)
printf '%s\n' "$BARRIER_FAILURE" | grep -q '^code=durability-barrier-failed$'
[ "$BEFORE_BARRIER_FAILURE" = "$(sha256sum "$SANDBOX/system/fonts/"*.ttf)" ]
[ ! -e "$SANDBOX/.font-transaction" ]
printf '%s\n' '#!/usr/bin/env sh' 'exit 0' >"$SANDBOX/bin/sync"
rm -f "$SANDBOX/skip_mount"

# Fixed backup paths cannot be dangling symlinks that redirect root writes.
printf '%s\n' preserve >"$SANDBOX/external-backup-target"
ln -s "$SANDBOX/external-backup-target" "$SANDBOX/.selection-backup"
UNSAFE_BACKUP_RESULT=$(apply vazirmatn 2>&1 || true)
printf '%s\n' "$UNSAFE_BACKUP_RESULT" | grep -q '^code=unsafe-transaction-state$'
[ "$(sed -n '1p' "$SANDBOX/external-backup-target")" = preserve ]
rm -f "$SANDBOX/.selection-backup"

# A state-write failure must roll back all four files and retain skip_mount.
apply estedad >/dev/null
BEFORE_STATE_FAILURE=$(sha256sum "$SANDBOX/system/fonts/"*.ttf)
rm "$SANDBOX/state/selected-font"
mkdir "$SANDBOX/state/selected-font"
STATE_FAILURE=$(apply vazirmatn 2>&1 || true)
printf '%s\n' "$STATE_FAILURE" | grep -q '^code=state-write-failed$'
[ "$BEFORE_STATE_FAILURE" = "$(sha256sum "$SANDBOX/system/fonts/"*.ttf)" ]
[ -e "$SANDBOX/skip_mount" ]
rmdir "$SANDBOX/state/selected-font"
printf '%s\n' estedad >"$SANDBOX/state/selected-font"
rm -f "$SANDBOX/skip_mount"

apply system-default | grep -q '^status=ok$'
[ -e "$SANDBOX/skip_mount" ]
[ ! -d "$SANDBOX/system/fonts" ]
[ "$(sed -n '1p' "$SANDBOX/state/selected-font")" = "system-default" ]

STATUS=$(PFS_MODULE_DIR="$SANDBOX" PFS_DATA_DIR="$SANDBOX/data" PFS_ADB_ROOT="$SANDBOX/adb" \
  PFS_EFFECTIVE_FONT_DIR="$SANDBOX/effective" sh "$SANDBOX/scripts/get-status.sh")
printf '%s\n' "$STATUS" | grep -q '^active=estedad$'
printf '%s\n' "$STATUS" | grep -q '^selected=system-default$'
printf '%s\n' "$STATUS" | grep -q '^restart_required=true$'

for TARGET in "$SANDBOX/effective/"*.ttf; do printf '%s' rom-default >"$TARGET"; done
STATUS=$(PFS_MODULE_DIR="$SANDBOX" PFS_DATA_DIR="$SANDBOX/data" PFS_ADB_ROOT="$SANDBOX/adb" \
  PFS_EFFECTIVE_FONT_DIR="$SANDBOX/effective" sh "$SANDBOX/scripts/get-status.sh")
printf '%s\n' "$STATUS" | grep -q '^active=unknown$'
printf '%s\n' "$STATUS" | grep -q '^selected=system-default$'
printf '%s\n' "$STATUS" | grep -q '^restart_required=unknown$'

apply estedad | grep -q '^status=ok$'
assert_mapping estedad

printf '%s\n' invalid-target.ttf >"$SANDBOX/state/supported-targets"
if apply vazirmatn >/dev/null 2>&1; then
  echo "Invalid target allowlist was accepted" >&2
  exit 1
fi
cp "$PROJECT_DIR/state/supported-targets" "$SANDBOX/state/supported-targets"

# A power-loss-visible committed marker is trusted only after the selected
# state and all four new overlay hashes verify. Otherwise the durable backup is
# restored before any later operation proceeds.
cp -R "$SANDBOX/system/fonts" "$SANDBOX/.font-backup"
cp "$SANDBOX/state/selected-font" "$SANDBOX/.selection-backup"
cp "$SANDBOX/assets/fonts/vazirmatn/regular.ttf" "$SANDBOX/system/fonts/NotoNaskhArabicUI-Regular.ttf"
cp "$SANDBOX/assets/fonts/vazirmatn/regular.ttf" "$SANDBOX/system/fonts/NotoNaskhArabic-Regular.ttf"
cp "$SANDBOX/assets/fonts/vazirmatn/bold.ttf" "$SANDBOX/system/fonts/NotoNaskhArabicUI-Bold.ttf"
cp "$SANDBOX/assets/fonts/vazirmatn/bold.ttf" "$SANDBOX/system/fonts/NotoNaskhArabic-Bold.ttf"
printf '%s' torn >"$SANDBOX/system/fonts/NotoNaskhArabicUI-Regular.ttf"
printf '%s\n' vazirmatn >"$SANDBOX/state/selected-font"
printf '%s\n' \
  'phase=committed' \
  'selection=vazirmatn' \
  'had_overlay=1' \
  'had_state=1' >"$SANDBOX/.font-transaction"

printf '%s' broken >"$SANDBOX/assets/fonts/sahel/regular.ttf"
# A failed durability barrier while downgrading an invalid committed marker
# must leave both rollback backups and a retryable transaction in place.
printf '%s\n' '#!/usr/bin/env sh' 'exit 70' >"$SANDBOX/bin/sync"
RECOVERY_BARRIER_FAILURE=$(apply sahel 2>&1 || true)
printf '%s\n' "$RECOVERY_BARRIER_FAILURE" | grep -q '^code=recovery-durability-failed$'
[ -d "$SANDBOX/.font-backup" ]
[ -f "$SANDBOX/.selection-backup" ]
[ "$(sed -n 's/^phase=//p' "$SANDBOX/.font-transaction")" = prepared ]
printf '%s\n' '#!/usr/bin/env sh' 'exit 0' >"$SANDBOX/bin/sync"
if apply sahel >/dev/null 2>&1; then
  echo "Corrupt font asset was accepted" >&2
  exit 1
fi
cmp "$SANDBOX/assets/fonts/estedad/regular.ttf" "$SANDBOX/system/fonts/NotoNaskhArabicUI-Regular.ttf"
cmp "$SANDBOX/assets/fonts/estedad/regular.ttf" "$SANDBOX/system/fonts/NotoNaskhArabic-Regular.ttf"
cmp "$SANDBOX/assets/fonts/estedad/bold.ttf" "$SANDBOX/system/fonts/NotoNaskhArabicUI-Bold.ttf"
cmp "$SANDBOX/assets/fonts/estedad/bold.ttf" "$SANDBOX/system/fonts/NotoNaskhArabic-Bold.ttf"
[ -e "$SANDBOX/skip_mount" ]
[ ! -e "$SANDBOX/.font-backup" ]
[ ! -e "$SANDBOX/.selection-backup" ]
[ ! -e "$SANDBOX/.font-transaction" ]
[ "$(sed -n '1p' "$SANDBOX/state/selected-font")" = estedad ]

STATUS=$(PFS_MODULE_DIR="$SANDBOX" PFS_DATA_DIR="$SANDBOX/data" PFS_ADB_ROOT="$SANDBOX/adb" \
  PFS_EFFECTIVE_FONT_DIR="$SANDBOX/effective" sh "$SANDBOX/scripts/get-status.sh")
printf '%s\n' "$STATUS" | grep -q '^selected=system-default$'
printf '%s\n' "$STATUS" | grep -q '^layout=valid$'

echo "Apply-script tests passed"
