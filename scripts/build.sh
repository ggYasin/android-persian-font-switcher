#!/usr/bin/env sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
OUTPUT=${1:-"$PROJECT_DIR/Persian-Font-Switcher-v0.1.0-rc3.zip"}
FILE_LIST="$PROJECT_DIR/scripts/payload-files.txt"
STAGE=$(mktemp -d)
trap 'rm -rf -- "$STAGE"' EXIT HUP INT TERM

python3 "$PROJECT_DIR/tests/validate_project.py" --source-only

while IFS= read -r RELATIVE || [ -n "$RELATIVE" ]; do
  case "$RELATIVE" in
    ''|'#'*) continue ;;
    /*|*'..'*) echo "Unsafe payload path: $RELATIVE" >&2; exit 1 ;;
  esac
  mkdir -p "$STAGE/$(dirname -- "$RELATIVE")"
  cp "$PROJECT_DIR/$RELATIVE" "$STAGE/$RELATIVE"
done <"$FILE_LIST"

find "$STAGE" -type d -exec chmod 0755 {} +
find "$STAGE" -type f -exec chmod 0644 {} +
chmod 0755 "$STAGE/customize.sh" "$STAGE/scripts/"*.sh
chmod 0600 "$STAGE/state/"*
find "$STAGE" -exec touch -t 202401010000 {} +

rm -f -- "$OUTPUT"
(
  cd "$STAGE"
  LC_ALL=C sort "$FILE_LIST" | sed '/^[[:space:]]*$/d; /^[[:space:]]*#/d' | zip -X -9 "$OUTPUT" -@
)

sha256sum "$OUTPUT"
