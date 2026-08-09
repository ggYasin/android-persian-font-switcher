#!/system/bin/sh
set -u

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$SCRIPT_DIR/lib.sh"

PREVIEW_ROOT="$PFS_DIR/webroot/custom-fonts"
STAGE_ROOT="$PFS_DIR/.custom-preview-stage"
BACKUP_ROOT="$PFS_DIR/.custom-preview-backup"
LOCK_ROOT="$PFS_DATA_DIR/.preview-sync-lock"
QUARANTINE_ROOT="$PFS_DATA_DIR/quarantine"
QUARANTINE_LOG="$QUARANTINE_ROOT/skipped-custom-data.log"
QUARANTINE_TMP=""
LOCK_ACQUIRED=0
STALE_LOCK_RECOVERED=0
COPIED=0
SKIPPED=0

cleanup() {
  rm -rf "$STAGE_ROOT" 2>/dev/null || true
  [ -z "$QUARANTINE_TMP" ] || rm -f "$QUARANTINE_TMP" 2>/dev/null || true
  if [ -d "$BACKUP_ROOT" ] && [ ! -L "$BACKUP_ROOT" ] \
    && [ ! -e "$PREVIEW_ROOT" ] && [ ! -L "$PREVIEW_ROOT" ]; then
    mv "$BACKUP_ROOT" "$PREVIEW_ROOT" 2>/dev/null || true
  fi
  if [ "$LOCK_ACQUIRED" -eq 1 ]; then
    pfs_release_lock "$LOCK_ROOT"
  fi
}
trap cleanup 0
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

prepare_preview_transaction_paths() {
  for PFS_PREVIEW_PATH in "$PREVIEW_ROOT" "$STAGE_ROOT" "$BACKUP_ROOT"; do
    if [ -e "$PFS_PREVIEW_PATH" ] || [ -L "$PFS_PREVIEW_PATH" ]; then
      [ -d "$PFS_PREVIEW_PATH" ] && [ ! -L "$PFS_PREVIEW_PATH" ] || return 1
    fi
  done
  if [ -d "$BACKUP_ROOT" ]; then
    if [ ! -e "$PREVIEW_ROOT" ] && [ ! -L "$PREVIEW_ROOT" ]; then
      mv "$BACKUP_ROOT" "$PREVIEW_ROOT" || return 1
    else
      rm -rf "$BACKUP_ROOT" || return 1
    fi
  fi
  rm -rf "$STAGE_ROOT" || return 1
  return 0
}

finish_without_data() {
  if ! prepare_preview_transaction_paths || ! mkdir "$STAGE_ROOT"; then
    printf '%s\n' "status=warning" "code=preview-stage-unavailable" \
      "message=No custom-font data exists, but an empty preview directory could not be prepared. Installation may continue."
    exit 0
  fi
  if [ -d "$PREVIEW_ROOT" ]; then
    if ! mv "$PREVIEW_ROOT" "$BACKUP_ROOT"; then
      printf '%s\n' "status=warning" "code=preview-replace-unavailable" \
        "message=No custom-font data exists; stale module-local previews could not be replaced. Installation may continue."
      exit 0
    fi
  fi
  if ! mv "$STAGE_ROOT" "$PREVIEW_ROOT"; then
    [ ! -d "$BACKUP_ROOT" ] || mv "$BACKUP_ROOT" "$PREVIEW_ROOT" 2>/dev/null || true
    printf '%s\n' "status=warning" "code=preview-replace-unavailable" \
      "message=No custom-font data exists; an empty preview directory could not be installed. Installation may continue."
    exit 0
  fi
  rm -rf "$BACKUP_ROOT" 2>/dev/null || true
  trap - 0 HUP INT TERM
  printf '%s\n' "status=ok" "code=no-custom-data" \
    "message=No persistent custom fonts were found; preview restoration was not needed."
  exit 0
}

# A fresh installation has no persistent registry. Do not create or lock an
# external data directory merely to produce an empty WebUI preview directory.
if ! pfs_custom_storage_safe; then
  printf '%s\n' "status=warning" "code=unsafe-custom-root" \
    "message=Persistent custom-font storage is not a safe directory; it was preserved and skipped. Installation may continue."
  exit 0
fi
if [ ! -e "$PFS_CUSTOM_DIR" ]; then
  finish_without_data
fi

if [ ! -d "$PFS_CUSTOM_DIR" ] || [ -L "$PFS_CUSTOM_DIR" ]; then
  printf '%s\n' "status=warning" "code=unsafe-custom-root" \
    "message=Persistent custom-font storage is not a safe directory; it was preserved and skipped. Installation may continue."
  exit 0
fi

if ! ls "$PFS_CUSTOM_DIR" >/dev/null 2>&1; then
  printf '%s\n' "status=warning" "code=custom-root-unreadable" \
    "message=Persistent custom-font storage is currently unreadable. It was preserved and preview restoration is deferred."
  exit 0
fi

# The kernel releases flock ownership on every process exit, including SIGKILL
# and power loss. The regular lock file itself is intentionally retained.
if ! pfs_acquire_lock "$LOCK_ROOT"; then
  if [ "${PFS_LOCK_ERROR:-unavailable}" = "busy" ]; then
    PREVIEW_LOCK_CODE=preview-sync-busy
    PREVIEW_LOCK_MESSAGE="Custom preview synchronization is already active. Persistent fonts were preserved; restoration is deferred."
  else
    PREVIEW_LOCK_CODE=preview-lock-unavailable
    PREVIEW_LOCK_MESSAGE="The preview operation lock is unavailable. Persistent fonts were preserved; restoration is deferred."
  fi
  printf '%s\n' "status=warning" "code=$PREVIEW_LOCK_CODE" "message=$PREVIEW_LOCK_MESSAGE"
  exit 0
fi
LOCK_ACQUIRED=1
STALE_LOCK_RECOVERED=$PFS_LOCK_RECOVERED

if ! prepare_preview_transaction_paths; then
  printf '%s\n' "status=warning" "code=unsafe-preview-transaction" \
    "message=Interrupted preview transaction data is unsafe. Persistent fonts were preserved; restoration is deferred."
  exit 0
fi

if ! mkdir "$STAGE_ROOT"; then
  printf '%s\n' "status=warning" "code=preview-stage-unavailable" \
    "message=Custom preview staging is unavailable. Persistent fonts were preserved; restoration is deferred."
  exit 0
fi

# The quarantine directory contains diagnostics only. Original user files stay
# exactly where they are, so malformed, stale, or temporarily unreadable data is
# never silently deleted or moved during installation.
if { [ ! -e "$QUARANTINE_ROOT" ] && [ ! -L "$QUARANTINE_ROOT" ] \
    && mkdir "$QUARANTINE_ROOT" 2>/dev/null; } \
  || { [ -d "$QUARANTINE_ROOT" ] && [ ! -L "$QUARANTINE_ROOT" ]; }; then
  chmod 0700 "$QUARANTINE_ROOT" 2>/dev/null || true
  PFS_QUARANTINE_CANDIDATE="$QUARANTINE_ROOT/.skipped-custom-data.$$.tmp"
  if : >"$PFS_QUARANTINE_CANDIDATE" 2>/dev/null; then
    QUARANTINE_TMP="$PFS_QUARANTINE_CANDIDATE"
  fi
fi

for CUSTOM_PATH in "$PFS_CUSTOM_DIR"/*; do
  [ -e "$CUSTOM_PATH" ] || [ -L "$CUSTOM_PATH" ] || continue
  CUSTOM_ID=${CUSTOM_PATH##*/}
  DIAGNOSTIC_ID="$CUSTOM_ID"
  if ! pfs_custom_dir "$CUSTOM_ID" >/dev/null 2>&1; then
    DIAGNOSTIC_ID="unrecognized-entry"
  fi
  if [ -L "$CUSTOM_PATH" ] || [ ! -d "$CUSTOM_PATH" ] || ! pfs_custom_valid "$CUSTOM_ID" 2>/dev/null; then
    SKIPPED=$((SKIPPED + 1))
    printf '%s\n' "skipped_custom=$DIAGNOSTIC_ID"
    [ -z "$QUARANTINE_TMP" ] \
      || printf '%s\n' "$DIAGNOSTIC_ID: invalid, incompatible, or unreadable; original preserved in place" >>"$QUARANTINE_TMP" 2>/dev/null \
      || true
    continue
  fi

  if ! mkdir -p "$STAGE_ROOT/$CUSTOM_ID" \
    || ! cp "$CUSTOM_PATH/regular.ttf" "$STAGE_ROOT/$CUSTOM_ID/regular.ttf" \
    || ! cp "$CUSTOM_PATH/bold.ttf" "$STAGE_ROOT/$CUSTOM_ID/bold.ttf" \
    || ! chmod 0644 "$STAGE_ROOT/$CUSTOM_ID/regular.ttf" "$STAGE_ROOT/$CUSTOM_ID/bold.ttf"; then
    rm -rf "$STAGE_ROOT/$CUSTOM_ID" 2>/dev/null || true
    SKIPPED=$((SKIPPED + 1))
    printf '%s\n' "skipped_custom=$DIAGNOSTIC_ID"
    [ -z "$QUARANTINE_TMP" ] \
      || printf '%s\n' "$DIAGNOSTIC_ID: preview copy failed; original preserved in place" >>"$QUARANTINE_TMP" 2>/dev/null \
      || true
    continue
  fi
  COPIED=$((COPIED + 1))
done

if [ -n "$QUARANTINE_TMP" ] && [ -f "$QUARANTINE_TMP" ]; then
  chmod 0600 "$QUARANTINE_TMP" 2>/dev/null || true
  mv -f "$QUARANTINE_TMP" "$QUARANTINE_LOG" 2>/dev/null || true
fi

if [ -d "$PREVIEW_ROOT" ]; then
  if ! mv "$PREVIEW_ROOT" "$BACKUP_ROOT"; then
    printf '%s\n' "status=warning" "code=preview-replace-unavailable" \
      "copied=$COPIED" "skipped=$SKIPPED" \
      "message=Existing previews could not be backed up. Persistent fonts were preserved; restoration is deferred."
    exit 0
  fi
fi
if ! mv "$STAGE_ROOT" "$PREVIEW_ROOT"; then
  [ ! -d "$BACKUP_ROOT" ] || mv "$BACKUP_ROOT" "$PREVIEW_ROOT" 2>/dev/null || true
  printf '%s\n' "status=warning" "code=preview-replace-unavailable" \
    "copied=$COPIED" "skipped=$SKIPPED" \
    "message=Prepared previews could not be activated. Persistent fonts were preserved; restoration is deferred."
  exit 0
fi
rm -rf "$BACKUP_ROOT" 2>/dev/null || true
pfs_release_lock "$LOCK_ROOT"
LOCK_ACQUIRED=0
trap - 0 HUP INT TERM

if [ "$SKIPPED" -gt 0 ]; then
  if [ -n "$QUARANTINE_TMP" ]; then
    PFS_SKIPPED_MESSAGE="Valid custom previews were restored; unusable entries were preserved and recorded in quarantine/skipped-custom-data.log."
  else
    PFS_SKIPPED_MESSAGE="Valid custom previews were restored and unusable entries were preserved; the private diagnostic log was unavailable."
  fi
  printf '%s\n' "status=warning" "code=custom-data-skipped" \
    "copied=$COPIED" "skipped=$SKIPPED" "recovered_stale_lock=$STALE_LOCK_RECOVERED" \
    "message=$PFS_SKIPPED_MESSAGE"
else
  printf '%s\n' "status=ok" "code=previews-restored" \
    "copied=$COPIED" "skipped=0" "recovered_stale_lock=$STALE_LOCK_RECOVERED" \
    "message=Custom previews synchronized."
fi
