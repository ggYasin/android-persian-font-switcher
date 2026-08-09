#!/usr/bin/env sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
VERSION=$(sed -n 's/^version=//p' "$PROJECT_DIR/module.prop")
printf '%s\n' "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$' \
  || { echo "module.prop version is missing or invalid" >&2; exit 1; }
ARCHIVE=${1:-"$PROJECT_DIR/Persian-Font-Switcher-v$VERSION.zip"}

python3 "$PROJECT_DIR/tests/validate_project.py" --archive "$ARCHIVE"
"$PROJECT_DIR/tests/test_apply.sh"
"$PROJECT_DIR/tests/test_custom_fonts.sh"
"$PROJECT_DIR/tests/test_installer_permissions.sh" "$ARCHIVE"

echo "Validated: $ARCHIVE"
sha256sum "$ARCHIVE"
