#!/system/bin/sh
set -eu

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

[ "$#" -eq 2 ] || fail invalid-arguments "Import requires an action and a trusted token."
ACTION=$1
TOKEN=$2
valid_token "$TOKEN" || fail invalid-token "Import token is invalid."

mkdir -p "$PFS_STAGING_DIR" "$PFS_CUSTOM_DIR"
chmod 0700 "$PFS_DATA_DIR" "$PFS_STAGING_DIR" "$PFS_CUSTOM_DIR"
IMPORT_DIR="$PFS_STAGING_DIR/$TOKEN"

case "$ACTION" in
  begin)
    rm -rf "$IMPORT_DIR"
    mkdir "$IMPORT_DIR"
    chmod 0700 "$IMPORT_DIR"
    printf '%s\n' \
      "status=ok" \
      "token=$TOKEN" \
      "regular_path=$IMPORT_DIR/regular.ttf" \
      "bold_path=$IMPORT_DIR/bold.ttf" \
      "name_path=$IMPORT_DIR/name.b64"
    ;;
  cancel)
    rm -rf "$IMPORT_DIR"
    printf '%s\n' "status=ok" "message=Import staging removed."
    ;;
  finish)
    [ -d "$IMPORT_DIR" ] || fail missing-stage "Import staging is missing." 3
    for FONT_FILE in "$IMPORT_DIR/regular.ttf" "$IMPORT_DIR/bold.ttf"; do
      [ -f "$FONT_FILE" ] || fail incomplete-import "Regular and Bold files are both required." 3
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

    [ -s "$IMPORT_DIR/name.b64" ] || fail invalid-name "A display name is required." 3
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
    rm -f "$IMPORT_DIR/name.txt" "$IMPORT_DIR/regular.expected.sha256" "$IMPORT_DIR/bold.expected.sha256"
    chmod 0600 "$IMPORT_DIR"/*

    FINAL_DIR="$PFS_CUSTOM_DIR/$CUSTOM_ID"
    NEW_DIR="$PFS_CUSTOM_DIR/.new-$TOKEN"
    BACKUP_DIR="$PFS_CUSTOM_DIR/.backup-$TOKEN"
    rm -rf "$NEW_DIR" "$BACKUP_DIR"
    mv "$IMPORT_DIR" "$NEW_DIR"
    if [ -d "$FINAL_DIR" ]; then
      mv "$FINAL_DIR" "$BACKUP_DIR"
    fi
    if ! mv "$NEW_DIR" "$FINAL_DIR"; then
      [ ! -d "$BACKUP_DIR" ] || mv "$BACKUP_DIR" "$FINAL_DIR"
      fail persist-failed "The custom font could not be persisted." 4
    fi
    rm -rf "$BACKUP_DIR"
    chmod 0700 "$FINAL_DIR"
    # Persistence already succeeded. A preview-copy problem is recoverable and
    # must not turn a licensed font import into an apparent data-loss failure.
    PREVIEW_RESULT=$(PFS_MODULE_DIR="$PFS_DIR" PFS_DATA_DIR="$PFS_DATA_DIR" \
      sh "$PFS_DIR/scripts/sync-custom.sh" 2>&1 || true)

    printf '%s\n' \
      "status=ok" \
      "id=$CUSTOM_ID" \
      "name_b64=$NAME_B64" \
      "regular_sha256=$REGULAR_HASH" \
      "bold_sha256=$BOLD_HASH" \
      "message=Custom font imported and persisted. Preview synchronization is best-effort." \
      "preview_result=$(printf '%s' "$PREVIEW_RESULT" | tr '\n' ';' | cut -c1-512)"
    ;;
  *) fail invalid-action "Unknown import action." ;;
esac
