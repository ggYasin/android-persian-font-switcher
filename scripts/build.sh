#!/usr/bin/env sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
VERSION=$(sed -n 's/^version=//p' "$PROJECT_DIR/module.prop")
printf '%s\n' "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$' \
  || { echo "module.prop version is missing or invalid" >&2; exit 1; }
for REQUIRED_COMMAND in python3 zip sha256sum; do
  command -v "$REQUIRED_COMMAND" >/dev/null 2>&1 \
    || { echo "Required build command is missing: $REQUIRED_COMMAND" >&2; exit 1; }
done
OUTPUT=${1:-"$PROJECT_DIR/Persian-Font-Switcher-v$VERSION.zip"}
case "$OUTPUT" in
  /*) ;;
  *) OUTPUT="$(pwd -P)/$OUTPUT" ;;
esac
FILE_LIST="$PROJECT_DIR/scripts/payload-files.txt"
STAGE=$(mktemp -d)
trap 'rm -rf -- "$STAGE"' 0 HUP INT TERM

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
