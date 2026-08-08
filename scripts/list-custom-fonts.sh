#!/system/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$SCRIPT_DIR/lib.sh"

# Installation may safely defer preview restoration when persistent storage is
# busy or temporarily unreadable. Retry best-effort when the WebUI is opened.
PFS_MODULE_DIR="$PFS_DIR" PFS_DATA_DIR="$PFS_DATA_DIR" \
  sh "$PFS_DIR/scripts/sync-custom.sh" >/dev/null 2>&1 || true

printf '%s\n' "status=ok"
[ -d "$PFS_CUSTOM_DIR" ] || exit 0

for CUSTOM_PATH in "$PFS_CUSTOM_DIR"/custom-*; do
  [ -d "$CUSTOM_PATH" ] || continue
  CUSTOM_ID=${CUSTOM_PATH##*/}
  pfs_custom_valid "$CUSTOM_ID" || continue
  NAME_B64=$(tr -d '\n' <"$CUSTOM_PATH/name.b64")
  REGULAR_HASH=$(pfs_read_hash_file "$CUSTOM_PATH/regular.sha256")
  BOLD_HASH=$(pfs_read_hash_file "$CUSTOM_PATH/bold.sha256")
  printf '%s\n' "custom=$CUSTOM_ID|$NAME_B64|$REGULAR_HASH|$BOLD_HASH"
done
