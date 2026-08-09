#!/system/bin/sh
set -eu
umask 077

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$SCRIPT_DIR/lib.sh"

fail() {
  printf '%s\n' "status=error" "code=$1" "message=$2"
  exit "${3:-2}"
}

valid_token() {
  [ "${#1}" -eq 32 ] || return 1
  case "$1" in *[!0-9a-f]*) return 1 ;; esac
}

valid_sfnt() {
  PFS_SFNT_MAGIC=$(od -An -tx1 -N4 "$1" 2>/dev/null | tr -d ' \n')
  case "$PFS_SFNT_MAGIC" in 00010000|4f54544f) return 0 ;; *) return 1 ;; esac
}

cleanup_staging() {
  PFS_STAGE_NOW=$(date +%s 2>/dev/null || printf '%s' 0)
  PFS_STAGES_CLEANED=0
  case "$PFS_STAGE_NOW" in *[!0-9]*|'') PFS_STAGE_NOW=0 ;; esac
  [ "$PFS_STAGE_NOW" -gt 0 ] || return 0
  for PFS_OLD_STAGE in "$PFS_STAGING_DIR"/*; do
    [ -d "$PFS_OLD_STAGE" ] && [ ! -L "$PFS_OLD_STAGE" ] || continue
    PFS_OLD_TOKEN=${PFS_OLD_STAGE##*/}
    valid_token "$PFS_OLD_TOKEN" || continue
    [ "$PFS_OLD_TOKEN" != "$TOKEN" ] || continue
    PFS_STAGE_CREATED=""
    if [ -f "$PFS_OLD_STAGE/created-at" ] && [ ! -L "$PFS_OLD_STAGE/created-at" ]; then
      IFS= read -r PFS_STAGE_CREATED <"$PFS_OLD_STAGE/created-at" 2>/dev/null || PFS_STAGE_CREATED=""
    fi
    case "$PFS_STAGE_CREATED" in *[!0-9]*|'') continue ;; esac
    PFS_STAGE_AGE=$((PFS_STAGE_NOW - PFS_STAGE_CREATED))
    if [ "$PFS_STAGE_AGE" -ge 86400 ]; then
      rm -rf "$PFS_OLD_STAGE"
      PFS_STAGES_CLEANED=$((PFS_STAGES_CLEANED + 1))
    fi
  done
}

[ "$#" -eq 2 ] || fail invalid-arguments "Import requires an action and a trusted token."
ACTION=$1
TOKEN=$2
valid_token "$TOKEN" || fail invalid-token "Import token is invalid."

for PFS_STORAGE_PATH in "$PFS_DATA_DIR" "$PFS_STAGING_DIR" "$PFS_CUSTOM_DIR"; do
  if [ -e "$PFS_STORAGE_PATH" ] || [ -L "$PFS_STORAGE_PATH" ]; then
    [ -d "$PFS_STORAGE_PATH" ] && [ ! -L "$PFS_STORAGE_PATH" ] \
      || fail unsafe-storage "Custom-font storage is not a safe directory." 3
  fi
done
mkdir -p "$PFS_STAGING_DIR" "$PFS_CUSTOM_DIR"
chmod 0700 "$PFS_DATA_DIR" "$PFS_STAGING_DIR" "$PFS_CUSTOM_DIR"
IMPORT_DIR="$PFS_STAGING_DIR/$TOKEN"

case "$ACTION" in
  begin)
    cleanup_staging
    rm -rf "$IMPORT_DIR"
    mkdir "$IMPORT_DIR"
    chmod 0700 "$IMPORT_DIR"
    date +%s >"$IMPORT_DIR/created-at"
    chmod 0600 "$IMPORT_DIR/created-at"
    printf '%s\n' \
      "status=ok" \
      "token=$TOKEN" \
      "stale_stages_cleaned=$PFS_STAGES_CLEANED" \
      "regular_path=$IMPORT_DIR/regular.ttf" \
      "bold_path=$IMPORT_DIR/bold.ttf" \
      "name_path=$IMPORT_DIR/name.b64"
    ;;
  cancel)
    rm -rf "$IMPORT_DIR"
    printf '%s\n' "status=ok" "message=Import staging removed."
    ;;
  finish)
    [ -d "$IMPORT_DIR" ] && [ ! -L "$IMPORT_DIR" ] || fail missing-stage "Import staging is missing or unsafe." 3
    [ -f "$IMPORT_DIR/created-at" ] && [ ! -L "$IMPORT_DIR/created-at" ] \
      || fail missing-stage "Import staging metadata is missing or unsafe." 3
    for STAGED_PATH in "$IMPORT_DIR"/* "$IMPORT_DIR"/.[!.]* "$IMPORT_DIR"/..?*; do
      [ -e "$STAGED_PATH" ] || [ -L "$STAGED_PATH" ] || continue
      STAGED_NAME=${STAGED_PATH##*/}
      case "$STAGED_NAME" in
        created-at|regular.ttf|bold.ttf|name.b64|regular.expected.sha256|bold.expected.sha256) ;;
        *) fail unexpected-stage-entry "Import staging contains an unexpected entry and was preserved for inspection." 3 ;;
      esac
      [ -f "$STAGED_PATH" ] && [ ! -L "$STAGED_PATH" ] \
        || fail unsafe-stage-entry "Import staging contains a non-regular or linked entry." 3
    done
    for FONT_FILE in "$IMPORT_DIR/regular.ttf" "$IMPORT_DIR/bold.ttf"; do
      [ -f "$FONT_FILE" ] && [ ! -L "$FONT_FILE" ] || fail incomplete-import "Regular and Bold files are both required and must be ordinary files." 3
      FONT_SIZE=$(wc -c <"$FONT_FILE" | tr -d ' ')
      [ "$FONT_SIZE" -ge 256 ] && [ "$FONT_SIZE" -le 16777216 ] \
        || fail invalid-font-size "Each font must be between 256 bytes and 16 MiB." 3
      valid_sfnt "$FONT_FILE" || fail invalid-font "A selected file is not a supported TrueType/OpenType font." 3
    done

    EXPECTED_REGULAR_HASH=$(pfs_read_hash_file "$IMPORT_DIR/regular.expected.sha256") \
      || fail missing-transfer-hash "Regular transfer integrity metadata is missing." 3
    EXPECTED_BOLD_HASH=$(pfs_read_hash_file "$IMPORT_DIR/bold.expected.sha256") \
      || fail missing-transfer-hash "Bold transfer integrity metadata is missing." 3
    RECEIVED_REGULAR_HASH=$(sha256sum "$IMPORT_DIR/regular.ttf" | awk '{print $1}')
    RECEIVED_BOLD_HASH=$(sha256sum "$IMPORT_DIR/bold.ttf" | awk '{print $1}')
    [ "$RECEIVED_REGULAR_HASH" = "$EXPECTED_REGULAR_HASH" ] \
      && [ "$RECEIVED_BOLD_HASH" = "$EXPECTED_BOLD_HASH" ] \
      || fail transfer-checksum-mismatch "A font changed during privileged transfer." 3

    [ -s "$IMPORT_DIR/name.b64" ] && [ ! -L "$IMPORT_DIR/name.b64" ] || fail invalid-name "A display name is required." 3
    NAME_B64=$(tr -d '\n' <"$IMPORT_DIR/name.b64")
    [ "${#NAME_B64}" -le 256 ] || fail invalid-name "The encoded display name is too long." 3
    case "$NAME_B64" in *[!A-Za-z0-9+/=]*) fail invalid-name "The display name encoding is invalid." 3 ;; esac
    if ! printf '%s' "$NAME_B64" | base64 -d >"$IMPORT_DIR/name.txt" 2>/dev/null; then
      fail invalid-name "The display name encoding is invalid." 3
    fi
    NAME_SIZE=$(wc -c <"$IMPORT_DIR/name.txt" | tr -d ' ')
    [ "$NAME_SIZE" -ge 1 ] && [ "$NAME_SIZE" -le 80 ] || fail invalid-name "The display name must be 1-80 UTF-8 bytes." 3
    if grep -q '[[:cntrl:]]' "$IMPORT_DIR/name.txt"; then
      fail invalid-name "The display name contains control characters." 3
    fi

    REGULAR_HASH="$RECEIVED_REGULAR_HASH"
    BOLD_HASH="$RECEIVED_BOLD_HASH"
    CUSTOM_ID="custom-$(printf '%s' "$REGULAR_HASH" | cut -c1-12)$(printf '%s' "$BOLD_HASH" | cut -c1-12)"
    printf '%s\n' "$REGULAR_HASH" >"$IMPORT_DIR/regular.sha256"
    printf '%s\n' "$BOLD_HASH" >"$IMPORT_DIR/bold.sha256"
    printf '%s\n' "$NAME_B64" >"$IMPORT_DIR/name.b64"
    rm -f "$IMPORT_DIR/name.txt" "$IMPORT_DIR/regular.expected.sha256" "$IMPORT_DIR/bold.expected.sha256" "$IMPORT_DIR/created-at"
    chmod 0600 \
      "$IMPORT_DIR/regular.ttf" \
      "$IMPORT_DIR/bold.ttf" \
      "$IMPORT_DIR/name.b64" \
      "$IMPORT_DIR/regular.sha256" \
      "$IMPORT_DIR/bold.sha256"

    FINAL_DIR="$PFS_CUSTOM_DIR/$CUSTOM_ID"
    LOCK_DIR="$PFS_DIR/.apply-lock"
    if ! pfs_acquire_lock "$LOCK_DIR"; then
      if [ "${PFS_LOCK_ERROR:-unavailable}" = "busy" ]; then
        fail busy "Another font operation is already in progress." 4
      fi
      fail lock-unavailable "The operation lock is unavailable; verify the required flock command and reinstall the module." 4
    fi
    IMPORT_LOCKED=1
    release_import_lock() {
      if [ "$IMPORT_LOCKED" -eq 1 ]; then
        pfs_release_lock "$LOCK_DIR"
      fi
    }
    trap release_import_lock 0
    trap 'exit 129' HUP
    trap 'exit 130' INT
    trap 'exit 143' TERM

    pfs_recover_delete_transaction \
      || fail unsafe-delete-transaction "Interrupted custom-font deletion data needs manual inspection." 4

    if [ -e "$FINAL_DIR" ]; then
      pfs_custom_valid "$CUSTOM_ID" || fail persist-conflict "An existing entry with this content ID is invalid and was preserved." 4
      NAME_TMP="$FINAL_DIR/.name.$$.tmp"
      printf '%s\n' "$NAME_B64" >"$NAME_TMP"
      chmod 0600 "$NAME_TMP"
      mv -f "$NAME_TMP" "$FINAL_DIR/name.b64"
      rm -rf "$IMPORT_DIR"
      IMPORT_RESULT=updated-existing
    else
      mv "$IMPORT_DIR" "$FINAL_DIR" || fail persist-failed "The custom font could not be persisted." 4
      chmod 0700 "$FINAL_DIR"
      IMPORT_RESULT=created
    fi
    # Persistence already succeeded. A preview-copy problem is recoverable and
    # must not turn a licensed font import into an apparent data-loss failure.
    PREVIEW_RESULT=$(PFS_MODULE_DIR="$PFS_DIR" PFS_DATA_DIR="$PFS_DATA_DIR" \
      sh "$PFS_DIR/scripts/sync-custom.sh" 2>&1 || true)
    IMPORT_LOCKED=0
    pfs_release_lock "$LOCK_DIR"
    trap - 0 HUP INT TERM

    printf '%s\n' \
      "status=ok" \
      "id=$CUSTOM_ID" \
      "import_result=$IMPORT_RESULT" \
      "name_b64=$NAME_B64" \
      "regular_sha256=$REGULAR_HASH" \
      "bold_sha256=$BOLD_HASH" \
      "message=Custom font imported and persisted. Preview synchronization is best-effort." \
      "preview_result=$(printf '%s' "$PREVIEW_RESULT" | tr '\n' ';' | cut -c1-512)"
    ;;
  *) fail invalid-action "Unknown import action." ;;
esac
