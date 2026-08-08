#!/system/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$SCRIPT_DIR/lib.sh"

SELECTED=$(pfs_read_selection)
if pfs_reboot_required; then
  REBOOT_REQUIRED=true
else
  REBOOT_REQUIRED=false
fi

if pfs_validate_targets; then
  TARGETS=$(tr '\n' ',' <"$PFS_TARGETS_FILE" | sed 's/,$//')
  LAYOUT=valid
else
  TARGETS=""
  LAYOUT=invalid
fi

printf '%s\n' \
  "status=ok" \
  "selected=$SELECTED" \
  "reboot_required=$REBOOT_REQUIRED" \
  "layout=$LAYOUT" \
  "targets=$TARGETS"

