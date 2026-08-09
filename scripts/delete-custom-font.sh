#!/system/bin/sh
set -eu
umask 077

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$SCRIPT_DIR/lib.sh"

fail() {
  printf '%s\n' "status=error" "code=$1" "message=$2"
  exit "${3:-2}"
}

[ "$#" -eq 1 ] || fail invalid-arguments "Exactly one custom font ID is required."
CUSTOM_ID=$1
CUSTOM_PATH=$(pfs_custom_dir "$CUSTOM_ID") || fail invalid-font-id "The custom font ID is invalid."
pfs_custom_storage_safe || fail unsafe-storage "Custom-font storage is not a safe directory." 3

LOCK_FILE="$PFS_DIR/.apply-lock"
if ! pfs_acquire_lock "$LOCK_FILE"; then
  if [ "${PFS_LOCK_ERROR:-unavailable}" = "busy" ]; then
    fail busy "Another font operation is already in progress." 4
  fi
  fail lock-unavailable "The operation lock is unavailable; verify the required flock command and reinstall the module." 4
fi
RECOVERED_STALE_LOCK=$PFS_LOCK_RECOVERED

cleanup() {
  pfs_release_lock "$LOCK_FILE"
}
trap cleanup 0
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

if ! pfs_recover_delete_transaction; then
  fail unsafe-transaction-state "An interrupted custom-font deletion could not be recovered safely; preserved data needs manual inspection." 6
fi
RECOVERED_DELETE=$PFS_DELETE_RECOVERED

if ! pfs_custom_valid "$CUSTOM_ID"; then
  fail invalid-font "The custom font is missing or failed integrity validation." 3
fi

SELECTED=$(pfs_read_selection)
if [ "$SELECTED" = "$CUSTOM_ID" ]; then
  fail selected-font "Switch to a bundled font or System Default before removing this custom font." 5
fi

DELETE_MARKER="$PFS_DATA_DIR/.delete-transaction"
DELETE_MARKER_TMP="$PFS_DATA_DIR/.delete-transaction.new"
DELETE_TRASH="$PFS_DATA_DIR/.deleted-custom-font"
for DELETE_STATE_PATH in "$DELETE_MARKER" "$DELETE_MARKER_TMP" "$DELETE_TRASH"; do
  [ ! -e "$DELETE_STATE_PATH" ] && [ ! -L "$DELETE_STATE_PATH" ] \
    || fail unsafe-transaction-state "Unexpected removal transaction data was preserved; retry after inspection." 6
done

printf '%s\n' "$CUSTOM_ID" >"$DELETE_MARKER_TMP" \
  || fail remove-failed "The removal transaction could not be recorded." 6
chmod 0600 "$DELETE_MARKER_TMP" \
  || fail remove-failed "The removal transaction metadata could not be protected." 6
mv "$DELETE_MARKER_TMP" "$DELETE_MARKER" \
  || fail remove-failed "The removal transaction could not be committed." 6

# The rename is the deletion commit point. If the process is killed afterward,
# the durable marker lets the next registry read/import/removal finish cleanup.
mv "$CUSTOM_PATH" "$DELETE_TRASH" \
  || fail remove-failed "The custom font could not be prepared for removal." 6
rm -rf "$DELETE_TRASH" \
  || fail remove-incomplete "The custom font was detached but cleanup is incomplete; refresh to recover." 6
rm -f "$DELETE_MARKER" \
  || fail remove-incomplete "The custom font was removed but transaction cleanup is incomplete; refresh to recover." 6

PREVIEW_RESULT=$(PFS_MODULE_DIR="$PFS_DIR" PFS_DATA_DIR="$PFS_DATA_DIR" \
  sh "$PFS_DIR/scripts/sync-custom.sh" 2>&1 || true)
pfs_release_lock "$LOCK_FILE"
trap - 0 HUP INT TERM

printf '%s\n' \
  "status=ok" \
  "removed=$CUSTOM_ID" \
  "recovered_stale_lock=$RECOVERED_STALE_LOCK" \
  "recovered_delete=$RECOVERED_DELETE" \
  "message=Custom font removed from persistent storage." \
  "preview_result=$(printf '%s' "$PREVIEW_RESULT" | tr '\n' ';' | cut -c1-512)"
