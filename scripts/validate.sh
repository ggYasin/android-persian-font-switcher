#!/usr/bin/env sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
ARCHIVE=${1:-"$PROJECT_DIR/Persian-Font-Switcher-v0.1.0-rc2.zip"}

python3 "$PROJECT_DIR/tests/validate_project.py" --archive "$ARCHIVE"
"$PROJECT_DIR/tests/test_apply.sh"
"$PROJECT_DIR/tests/test_installer_permissions.sh" "$ARCHIVE"

echo "Validated: $ARCHIVE"
sha256sum "$ARCHIVE"
