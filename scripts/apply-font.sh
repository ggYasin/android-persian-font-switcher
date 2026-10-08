#!/system/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$SCRIPT_DIR/lib.sh"

if [ "$#" -ne 1 ]; then
  printf '%s\n' "status=error" "code=invalid-arguments" "message=Exactly one allowlisted font ID is required."
  exit 2
fi

FONT_ID="$1"
if ! pfs_valid_selection "$FONT_ID"; then
  printf '%s\n' "status=error" "code=invalid-font-id" "message=Unknown or invalid font ID."
  exit 2
fi

if ! pfs_validate_targets; then
  printf '%s\n' "status=error" "code=invalid-target-layout" "message=Supported target state is missing or invalid; reinstall the module."
  exit 3
fi

LOCK_FILE="$PFS_DIR/.apply-lock"
if ! pfs_acquire_lock "$LOCK_FILE"; then
  if [ "${PFS_LOCK_ERROR:-unavailable}" = "busy" ]; then
    printf '%s\n' "status=error" "code=busy" "message=Another font operation is already in progress."
    exit 4
  fi
  printf '%s\n' "status=error" "code=lock-unavailable" "message=The operation lock is unavailable; verify the required flock command and reinstall the module."
  exit 7
fi
RECOVERED_STALE_LOCK=$PFS_LOCK_RECOVERED
trap 'pfs_release_lock "$LOCK_FILE"' 0
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

GENERATION=none
if [ "$FONT_ID" != "system-default" ]; then
  if pfs_resolve_verified "$FONT_ID"; then
    :
  else
    case "$?" in
      2) printf '%s\n' "status=error" "code=missing-font-asset" "message=The selected font assets are incomplete." ;;
      3) printf '%s\n' "status=error" "code=font-checksum-mismatch" "message=The selected font failed integrity validation." ;;
      *) printf '%s\n' "status=error" "code=font-resolution-failed" "message=The selected font could not be resolved safely." ;;
    esac
    exit 5
  fi

  # Installation only records the choice; boot staging prepares the redirect.
  if [ "${PFS_SKIP_REDIRECT_STAGE:-0}" != "1" ]; then
    if ! pfs_prepare_redirect; then
      printf '%s\n' "status=error" "code=redirect-prepare-failed" "message=The font copies or patched font configuration could not be prepared; the previous selection is unchanged."
      exit 8
    fi
    GENERATION=$PFS_GENERATION
  fi
fi

if ! pfs_write_selection "$FONT_ID"; then
  printf '%s\n' "status=error" "code=state-write-failed" "message=Font state could not be saved; the previous selection remains in effect."
  exit 6
fi
# An explicit user choice re-arms activation after a tripped boot guard.
pfs_guard_clear
sync 2>/dev/null || true

if [ "${PFS_SKIP_REDIRECT_STAGE:-0}" = "1" ]; then
  MESSAGE="Font selection recorded; it is activated at the next boot."
else
  MESSAGE="Font selection staged. Reboot, or use Apply now, to activate it."
fi
printf '%s\n' \
  "status=ok" \
  "selected=$FONT_ID" \
  "config_backend=$PFS_CONFIG_BACKEND" \
  "recovered_stale_lock=$RECOVERED_STALE_LOCK" \
  "generation=$GENERATION" \
  "restart_required=true" \
  "message=$MESSAGE"
