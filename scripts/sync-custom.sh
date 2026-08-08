#!/system/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$SCRIPT_DIR/lib.sh"

PREVIEW_ROOT="$PFS_DIR/webroot/custom-fonts"
STAGE_ROOT="$PFS_DIR/.custom-preview-stage.$$"
BACKUP_ROOT="$PFS_DIR/.custom-preview-backup.$$"
LOCK_ROOT="$PFS_DATA_DIR/.preview-sync-lock"
LOCK_ACQUIRED=0

cleanup() {
  rm -rf "$STAGE_ROOT"
  if [ -d "$BACKUP_ROOT" ] && [ ! -d "$PREVIEW_ROOT" ]; then
    mv "$BACKUP_ROOT" "$PREVIEW_ROOT" 2>/dev/null || true
  fi
  if [ "$LOCK_ACQUIRED" -eq 1 ]; then
    rmdir "$LOCK_ROOT" 2>/dev/null || true
  fi
}
trap cleanup EXIT HUP INT TERM

mkdir -p "$PFS_DATA_DIR"
chmod 0700 "$PFS_DATA_DIR"
if ! mkdir "$LOCK_ROOT" 2>/dev/null; then
  printf '%s\n' "status=error" "code=busy" "message=Custom preview synchronization is already running."
  exit 4
fi
LOCK_ACQUIRED=1

mkdir -p "$STAGE_ROOT"
if [ -d "$PFS_CUSTOM_DIR" ]; then
  for CUSTOM_PATH in "$PFS_CUSTOM_DIR"/custom-*; do
    [ -d "$CUSTOM_PATH" ] || continue
    CUSTOM_ID=${CUSTOM_PATH##*/}
    pfs_custom_valid "$CUSTOM_ID" || continue
    mkdir -p "$STAGE_ROOT/$CUSTOM_ID"
    cp "$CUSTOM_PATH/regular.ttf" "$STAGE_ROOT/$CUSTOM_ID/regular.ttf"
    cp "$CUSTOM_PATH/bold.ttf" "$STAGE_ROOT/$CUSTOM_ID/bold.ttf"
    chmod 0644 "$STAGE_ROOT/$CUSTOM_ID/regular.ttf" "$STAGE_ROOT/$CUSTOM_ID/bold.ttf"
  done
fi

if [ -d "$PREVIEW_ROOT" ]; then
  mv "$PREVIEW_ROOT" "$BACKUP_ROOT"
fi
mv "$STAGE_ROOT" "$PREVIEW_ROOT"
rm -rf "$BACKUP_ROOT"
rmdir "$LOCK_ROOT"
LOCK_ACQUIRED=0
trap - EXIT HUP INT TERM

printf '%s\n' "status=ok" "message=Custom previews synchronized."
