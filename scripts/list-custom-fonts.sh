#!/system/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$SCRIPT_DIR/lib.sh"

LOCK_FILE="$PFS_DIR/.apply-lock"
if ! pfs_acquire_lock "$LOCK_FILE"; then
  if [ "${PFS_LOCK_ERROR:-unavailable}" = "busy" ]; then
    printf '%s\n' "status=error" "code=busy" "message=Another font operation is in progress; retry the custom-font list."
    exit 4
  fi
  printf '%s\n' "status=error" "code=lock-unavailable" "message=The operation lock is unavailable; reinstall the module."
  exit 4
fi
cleanup() {
  pfs_release_lock "$LOCK_FILE"
}
trap cleanup 0
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

if ! pfs_recover_delete_transaction; then
  printf '%s\n' "status=error" "code=unsafe-delete-transaction" "message=Interrupted custom-font deletion data needs manual inspection."
  exit 5
fi

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

pfs_release_lock "$LOCK_FILE"
trap - 0 HUP INT TERM
