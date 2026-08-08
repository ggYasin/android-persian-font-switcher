#!/system/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$SCRIPT_DIR/lib.sh"

if [ "$#" -ne 1 ]; then
  printf '%s\n' "status=error" "code=invalid-arguments" "message=Exactly one allowlisted font ID is required."
  exit 2
fi

FONT_ID="$1"
if ! pfs_valid_selection "$FONT_ID"; then
  printf '%s\n' "status=error" "code=invalid-font-id" "message=Unknown or invalid font ID."
  exit 2
fi

if ! pfs_validate_targets; then
  printf '%s\n' "status=error" "code=invalid-target-layout" "message=Supported target state is missing or invalid; reinstall the module."
  exit 3
fi

LOCK_DIR="$PFS_DIR/.apply-lock"
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  printf '%s\n' "status=error" "code=busy" "message=Another font operation is already in progress."
  exit 4
fi

STAGE_DIR="$PFS_DIR/.font-stage.$$"
BACKUP_DIR="$PFS_DIR/.font-backup.$$"
COMMITTED=0
SWAPPED=0

cleanup() {
  rm -rf "$STAGE_DIR"
  if [ "$COMMITTED" -eq 0 ] && [ "$SWAPPED" -eq 1 ] && [ -d "$BACKUP_DIR" ] && [ ! -d "$PFS_DIR/system/fonts" ]; then
    mv "$BACKUP_DIR" "$PFS_DIR/system/fonts" 2>/dev/null || true
  fi
  if [ "$COMMITTED" -eq 1 ]; then
    rm -rf "$BACKUP_DIR"
  fi
  rmdir "$LOCK_DIR" 2>/dev/null || true
}
trap cleanup EXIT HUP INT TERM

mkdir -p "$STAGE_DIR/system/fonts"
pfs_enable_skip_mount

if [ "$FONT_ID" != "system-default" ]; then
  RECORD=$(pfs_manifest_record "$FONT_ID")
  REGULAR_REL=$(pfs_json_field "$RECORD" regular)
  BOLD_REL=$(pfs_json_field "$RECORD" bold)
  REGULAR_HASH=$(pfs_json_field "$RECORD" sha256Regular)
  BOLD_HASH=$(pfs_json_field "$RECORD" sha256Bold)

  if [ "$REGULAR_REL" != "assets/fonts/$FONT_ID/regular.ttf" ] \
    || [ "$BOLD_REL" != "assets/fonts/$FONT_ID/bold.ttf" ]; then
    printf '%s\n' "status=error" "code=unsafe-manifest-path" "message=Manifest font paths are not canonical."
    exit 5
  fi

  REGULAR_SOURCE="$PFS_DIR/$REGULAR_REL"
  BOLD_SOURCE="$PFS_DIR/$BOLD_REL"
  if [ ! -f "$REGULAR_SOURCE" ] || [ ! -f "$BOLD_SOURCE" ]; then
    printf '%s\n' "status=error" "code=missing-font-asset" "message=The selected font assets are incomplete."
    exit 5
  fi

  if [ "$(sha256sum "$REGULAR_SOURCE" | awk '{print $1}')" != "$REGULAR_HASH" ] \
    || [ "$(sha256sum "$BOLD_SOURCE" | awk '{print $1}')" != "$BOLD_HASH" ]; then
    printf '%s\n' "status=error" "code=font-checksum-mismatch" "message=The selected font failed integrity validation."
    exit 5
  fi

  while IFS= read -r TARGET || [ -n "$TARGET" ]; do
    WEIGHT=$(pfs_target_weight "$TARGET")
    case "$WEIGHT" in
      regular) SOURCE="$REGULAR_SOURCE" ;;
      bold) SOURCE="$BOLD_SOURCE" ;;
      *) exit 5 ;;
    esac
    cp "$SOURCE" "$STAGE_DIR/system/fonts/$TARGET"
    chmod 0644 "$STAGE_DIR/system/fonts/$TARGET"
  done <"$PFS_TARGETS_FILE"
fi

if [ -d "$PFS_DIR/system/fonts" ]; then
  mv "$PFS_DIR/system/fonts" "$BACKUP_DIR"
  SWAPPED=1
fi

if [ "$FONT_ID" = "system-default" ]; then
  rmdir "$STAGE_DIR/system/fonts"
else
  mv "$STAGE_DIR/system/fonts" "$PFS_DIR/system/fonts"
fi

if ! pfs_write_selection "$FONT_ID"; then
  rm -rf "$PFS_DIR/system/fonts"
  if [ -d "$BACKUP_DIR" ]; then
    mv "$BACKUP_DIR" "$PFS_DIR/system/fonts"
  fi
  printf '%s\n' "status=error" "code=state-write-failed" "message=Font state could not be saved; system overlay mounting remains safely disabled."
  exit 6
fi

pfs_mark_reboot_required
if [ "$FONT_ID" != "system-default" ]; then
  rm -f "$PFS_DIR/skip_mount"
fi
COMMITTED=1

printf '%s\n' \
  "status=ok" \
  "selected=$FONT_ID" \
  "config_backend=$PFS_CONFIG_BACKEND" \
  "reboot_required=true" \
  "message=Font selected successfully. Reboot required to apply system-wide."
