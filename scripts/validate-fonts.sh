#!/system/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$SCRIPT_DIR/lib.sh"

for FONT_ID in vazirmatn estedad sahel; do
  RECORD=$(pfs_manifest_record "$FONT_ID")
  [ -n "$RECORD" ] || exit 1
  for WEIGHT in regular bold; do
    case "$WEIGHT" in
      regular) HASH_FIELD=sha256Regular ;;
      bold) HASH_FIELD=sha256Bold ;;
    esac
    RELATIVE=$(pfs_json_field "$RECORD" "$WEIGHT")
    EXPECTED=$(pfs_json_field "$RECORD" "$HASH_FIELD")
    [ "$RELATIVE" = "assets/fonts/$FONT_ID/$WEIGHT.ttf" ] || exit 1
    [ -f "$PFS_DIR/$RELATIVE" ] || exit 1
    ACTUAL=$(sha256sum "$PFS_DIR/$RELATIVE" | awk '{print $1}')
    [ "$ACTUAL" = "$EXPECTED" ] || exit 1
  done
done

printf '%s\n' "status=ok" "message=All bundled font checksums are valid."
