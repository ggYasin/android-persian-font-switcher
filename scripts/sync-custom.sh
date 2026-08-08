#!/system/bin/sh
set -u

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$SCRIPT_DIR/lib.sh"

PREVIEW_ROOT="$PFS_DIR/webroot/custom-fonts"
STAGE_ROOT="$PFS_DIR/.custom-preview-stage.$$"
BACKUP_ROOT="$PFS_DIR/.custom-preview-backup.$$"
LOCK_ROOT="$PFS_DATA_DIR/.preview-sync-lock"
QUARANTINE_ROOT="$PFS_DATA_DIR/quarantine"
QUARANTINE_LOG="$QUARANTINE_ROOT/skipped-custom-data.log"
QUARANTINE_TMP="$QUARANTINE_ROOT/.skipped-custom-data.$$.tmp"
LOCK_ACQUIRED=0
STALE_LOCK_RECOVERED=0
COPIED=0
SKIPPED=0

cleanup() {
  rm -rf "$STAGE_ROOT" 2>/dev/null || true
  rm -f "$QUARANTINE_TMP" 2>/dev/null || true
  if [ -d "$BACKUP_ROOT" ] && [ ! -d "$PREVIEW_ROOT" ]; then
    mv "$BACKUP_ROOT" "$PREVIEW_ROOT" 2>/dev/null || true
  fi
  if [ "$LOCK_ACQUIRED" -eq 1 ]; then
    rm -f "$LOCK_ROOT/pid" 2>/dev/null || true
    rmdir "$LOCK_ROOT" 2>/dev/null || true
  fi
}
trap cleanup 0 HUP INT TERM

finish_without_data() {
  if ! mkdir -p "$STAGE_ROOT"; then
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

# A live WebUI import must not prevent installation. A lock without a live PID
# is stale rc3/legacy state: preserve it under quarantine and retry once.
if ! mkdir "$LOCK_ROOT" 2>/dev/null; then
  LOCK_PID=""
  if [ -f "$LOCK_ROOT/pid" ]; then
    IFS= read -r LOCK_PID <"$LOCK_ROOT/pid" 2>/dev/null || LOCK_PID=""
  fi
  case "$LOCK_PID" in *[!0-9]*|'') LOCK_PID="" ;; esac
  if [ -n "$LOCK_PID" ] && kill -0 "$LOCK_PID" 2>/dev/null; then
    printf '%s\n' "status=warning" "code=preview-sync-busy" \
      "message=Custom preview synchronization is already active. Persistent fonts were preserved; restoration is deferred."
    exit 0
  fi
  if mkdir -p "$QUARANTINE_ROOT" 2>/dev/null \
    && mv "$LOCK_ROOT" "$QUARANTINE_ROOT/stale-preview-sync-lock.$$" 2>/dev/null \
    && mkdir "$LOCK_ROOT" 2>/dev/null; then
    STALE_LOCK_RECOVERED=1
  else
    printf '%s\n' "status=warning" "code=stale-lock-unrecoverable" \
      "message=A stale preview lock could not be quarantined. Persistent fonts were preserved; restoration is deferred."
    exit 0
  fi
fi
LOCK_ACQUIRED=1
printf '%s\n' "$$" >"$LOCK_ROOT/pid" 2>/dev/null || true

if ! mkdir -p "$STAGE_ROOT"; then
  printf '%s\n' "status=warning" "code=preview-stage-unavailable" \
    "message=Custom preview staging is unavailable. Persistent fonts were preserved; restoration is deferred."
  exit 0
fi

# The quarantine directory contains diagnostics only. Original user files stay
# exactly where they are, so malformed, stale, or temporarily unreadable data is
# never silently deleted or moved during installation.
if mkdir -p "$QUARANTINE_ROOT" 2>/dev/null; then
  chmod 0700 "$QUARANTINE_ROOT" 2>/dev/null || true
  : >"$QUARANTINE_TMP" 2>/dev/null || true
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
    printf '%s\n' "$DIAGNOSTIC_ID: invalid, incompatible, or unreadable; original preserved in place" >>"$QUARANTINE_TMP" 2>/dev/null || true
    continue
  fi

  if ! mkdir -p "$STAGE_ROOT/$CUSTOM_ID" \
    || ! cp "$CUSTOM_PATH/regular.ttf" "$STAGE_ROOT/$CUSTOM_ID/regular.ttf" \
    || ! cp "$CUSTOM_PATH/bold.ttf" "$STAGE_ROOT/$CUSTOM_ID/bold.ttf" \
    || ! chmod 0644 "$STAGE_ROOT/$CUSTOM_ID/regular.ttf" "$STAGE_ROOT/$CUSTOM_ID/bold.ttf"; then
    rm -rf "$STAGE_ROOT/$CUSTOM_ID" 2>/dev/null || true
    SKIPPED=$((SKIPPED + 1))
    printf '%s\n' "skipped_custom=$DIAGNOSTIC_ID"
    printf '%s\n' "$DIAGNOSTIC_ID: preview copy failed; original preserved in place" >>"$QUARANTINE_TMP" 2>/dev/null || true
    continue
  fi
  COPIED=$((COPIED + 1))
done

if [ -f "$QUARANTINE_TMP" ]; then
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
rm -f "$LOCK_ROOT/pid" 2>/dev/null || true
rmdir "$LOCK_ROOT" 2>/dev/null || true
LOCK_ACQUIRED=0
trap - 0 HUP INT TERM

if [ "$SKIPPED" -gt 0 ]; then
  printf '%s\n' "status=warning" "code=custom-data-skipped" \
    "copied=$COPIED" "skipped=$SKIPPED" "recovered_stale_lock=$STALE_LOCK_RECOVERED" \
    "message=Valid custom previews were restored; unusable entries were preserved and recorded in quarantine/skipped-custom-data.log."
else
  printf '%s\n' "status=ok" "code=previews-restored" \
    "copied=$COPIED" "skipped=0" "recovered_stale_lock=$STALE_LOCK_RECOVERED" \
    "message=Custom previews synchronized."
fi
