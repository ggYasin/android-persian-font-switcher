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

LOCK_DIR="$PFS_DIR/.apply-lock"
if ! pfs_acquire_lock "$LOCK_DIR"; then
  if [ "${PFS_LOCK_ERROR:-unavailable}" = "busy" ]; then
    printf '%s\n' "status=error" "code=busy" "message=Another font operation is already in progress."
    exit 4
  fi
  printf '%s\n' "status=error" "code=lock-unavailable" "message=The operation lock is unavailable; verify the required flock command and reinstall the module."
  exit 7
fi
RECOVERED_STALE_LOCK=$PFS_LOCK_RECOVERED

STAGE_DIR="$PFS_DIR/.font-stage"
BACKUP_DIR="$PFS_DIR/.font-backup"
STATE_BACKUP="$PFS_DIR/.selection-backup"
TRANSACTION_MARKER="$PFS_DIR/.font-transaction"
TRANSACTION_TMP="$PFS_DIR/.font-transaction.new"
COMMITTED=0
MUTATION_STARTED=0
HAD_OVERLAY=0
HAD_STATE=0
trap 'pfs_release_lock "$LOCK_DIR"' 0
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

write_transaction_marker_values() {
  PFS_TRANSACTION_PHASE="$1"
  PFS_TRANSACTION_SELECTION="$2"
  PFS_TRANSACTION_HAD_OVERLAY="$3"
  PFS_TRANSACTION_HAD_STATE="$4"
  [ ! -L "$TRANSACTION_MARKER" ] && [ ! -L "$TRANSACTION_TMP" ] || return 1
  rm -f "$TRANSACTION_TMP" || return 1
  printf '%s\n' \
    "phase=$PFS_TRANSACTION_PHASE" \
    "selection=$PFS_TRANSACTION_SELECTION" \
    "had_overlay=$PFS_TRANSACTION_HAD_OVERLAY" \
    "had_state=$PFS_TRANSACTION_HAD_STATE" >"$TRANSACTION_TMP" || return 1
  chmod 0600 "$TRANSACTION_TMP" || { rm -f "$TRANSACTION_TMP"; return 1; }
  mv -f "$TRANSACTION_TMP" "$TRANSACTION_MARKER" || { rm -f "$TRANSACTION_TMP"; return 1; }
  return 0
}

write_transaction_marker() {
  write_transaction_marker_values "$1" "$FONT_ID" "$HAD_OVERLAY" "$HAD_STATE"
}

pfs_committed_selection_valid() {
  PFS_COMMITTED_ID="$1"
  [ -f "$PFS_STATE_FILE" ] && [ ! -L "$PFS_STATE_FILE" ] || return 1
  IFS= read -r PFS_COMMITTED_STATE <"$PFS_STATE_FILE" || return 1
  [ "$PFS_COMMITTED_STATE" = "$PFS_COMMITTED_ID" ] || return 1
  if [ "$PFS_COMMITTED_ID" = "system-default" ]; then
    [ ! -e "$PFS_DIR/system/fonts" ] && [ ! -L "$PFS_DIR/system/fonts" ]
    return $?
  fi

  pfs_resolve_font "$PFS_COMMITTED_ID" || return 1
  pfs_validate_targets || return 1
  [ -d "$PFS_DIR/system/fonts" ] && [ ! -L "$PFS_DIR/system/fonts" ] || return 1
  PFS_COMMITTED_COUNT=0
  for PFS_COMMITTED_PATH in \
    "$PFS_DIR/system/fonts"/* \
    "$PFS_DIR/system/fonts"/.[!.]* \
    "$PFS_DIR/system/fonts"/..?*; do
    [ -e "$PFS_COMMITTED_PATH" ] || [ -L "$PFS_COMMITTED_PATH" ] || continue
    PFS_COMMITTED_NAME=${PFS_COMMITTED_PATH##*/}
    pfs_allowed_target "$PFS_COMMITTED_NAME" || return 1
    [ -f "$PFS_COMMITTED_PATH" ] && [ ! -L "$PFS_COMMITTED_PATH" ] || return 1
    case "$(pfs_target_weight "$PFS_COMMITTED_NAME")" in
      regular) PFS_COMMITTED_HASH="$PFS_REGULAR_HASH" ;;
      bold) PFS_COMMITTED_HASH="$PFS_BOLD_HASH" ;;
      *) return 1 ;;
    esac
    [ "$(sha256sum "$PFS_COMMITTED_PATH" | awk '{print $1}')" = "$PFS_COMMITTED_HASH" ] || return 1
    PFS_COMMITTED_COUNT=$((PFS_COMMITTED_COUNT + 1))
  done
  [ "$PFS_COMMITTED_COUNT" -eq 4 ]
}

# Recover a transaction interrupted by SIGKILL or power loss. Kernel flock
# ownership disappears automatically; this marker and the fixed backup paths
# make the filesystem mutation itself recoverable.
if [ -f "$TRANSACTION_MARKER" ] && [ ! -L "$TRANSACTION_MARKER" ]; then
  RECOVERY_PHASE=$(sed -n 's/^phase=//p' "$TRANSACTION_MARKER")
  RECOVERY_SELECTION=$(sed -n 's/^selection=//p' "$TRANSACTION_MARKER")
  RECOVERY_HAD_OVERLAY=$(sed -n 's/^had_overlay=//p' "$TRANSACTION_MARKER")
  RECOVERY_HAD_STATE=$(sed -n 's/^had_state=//p' "$TRANSACTION_MARKER")
  case "$RECOVERY_PHASE:$RECOVERY_HAD_OVERLAY:$RECOVERY_HAD_STATE" in
    prepared:[01]:[01]|committed:[01]:[01]) ;;
    *)
      printf '%s\n' "status=error" "code=unsafe-transaction-state" "message=Interrupted transaction metadata is invalid; reinstall the module."
      exit 7
      ;;
  esac
  if [ "$RECOVERY_SELECTION" = "system-default" ]; then
    :
  elif [ -n "$(pfs_manifest_record "$RECOVERY_SELECTION")" ]; then
    :
  elif ! pfs_custom_dir "$RECOVERY_SELECTION" >/dev/null 2>&1; then
    printf '%s\n' "status=error" "code=unsafe-transaction-state" "message=Interrupted transaction selection is invalid; reinstall the module."
    exit 7
  fi
  if { [ -e "$BACKUP_DIR" ] || [ -L "$BACKUP_DIR" ]; } \
    && { [ ! -d "$BACKUP_DIR" ] || [ -L "$BACKUP_DIR" ]; }; then
    printf '%s\n' "status=error" "code=unsafe-transaction-state" "message=Interrupted overlay backup data is unsafe; reinstall the module."
    exit 7
  fi
  if { [ -e "$STATE_BACKUP" ] || [ -L "$STATE_BACKUP" ]; } \
    && { [ ! -f "$STATE_BACKUP" ] || [ -L "$STATE_BACKUP" ]; }; then
    printf '%s\n' "status=error" "code=unsafe-transaction-state" "message=Interrupted selection backup data is unsafe; reinstall the module."
    exit 7
  fi

  RECOVERY_COMMIT_INVALID=0
  if [ "$RECOVERY_PHASE" = "committed" ] \
    && ! pfs_committed_selection_valid "$RECOVERY_SELECTION"; then
    # Never enable or discard rollback data for a committed marker whose
    # payload/state did not survive storage ordering intact. Persist the phase
    # downgrade before consuming a backup so recovery remains retryable if it
    # is itself interrupted.
    if ! write_transaction_marker_values prepared "$RECOVERY_SELECTION" \
      "$RECOVERY_HAD_OVERLAY" "$RECOVERY_HAD_STATE" || ! sync; then
      printf '%s\n' "status=error" "code=recovery-durability-failed" "message=Invalid committed state could not be made safely retryable; rollback data was preserved."
      exit 7
    fi
    RECOVERY_PHASE=prepared
    RECOVERY_COMMIT_INVALID=1
  fi

  if [ "$RECOVERY_PHASE" = "committed" ]; then
    if [ "$RECOVERY_SELECTION" = "system-default" ]; then
      pfs_enable_skip_mount || {
        printf '%s\n' "status=error" "code=recovery-failed" "message=A committed System Default marker could not be restored; reinstall the module."
        exit 7
      }
    else
      rm -f "$PFS_DIR/skip_mount" || {
        printf '%s\n' "status=error" "code=recovery-failed" "message=A committed overlay could not be re-enabled; reinstall the module."
        exit 7
      }
    fi
    sync || {
      printf '%s\n' "status=error" "code=recovery-durability-failed" "message=A recovered committed overlay could not be committed to storage; recovery data was preserved."
      exit 7
    }
    rm -rf "$BACKUP_DIR" "$STAGE_DIR"
    rm -f "$STATE_BACKUP" "$TRANSACTION_MARKER" "$TRANSACTION_TMP"
  else
    pfs_enable_skip_mount || {
      printf '%s\n' "status=error" "code=recovery-failed" "message=An interrupted operation could not be made mount-safe; reinstall the module."
      exit 7
    }
    if [ -d "$BACKUP_DIR" ] && [ ! -L "$BACKUP_DIR" ]; then
      rm -rf "$PFS_DIR/system/fonts"
      mv "$BACKUP_DIR" "$PFS_DIR/system/fonts" || {
        printf '%s\n' "status=error" "code=recovery-failed" "message=An interrupted font overlay could not be restored safely; reinstall the module."
        exit 7
      }
    elif [ "$RECOVERY_HAD_OVERLAY" -eq 0 ]; then
      rm -rf "$PFS_DIR/system/fonts"
    elif [ "$RECOVERY_COMMIT_INVALID" -eq 1 ]; then
      printf '%s\n' "status=error" "code=recovery-failed" "message=A committed overlay failed verification and its prior backup is unavailable; reinstall the module."
      exit 7
    elif [ ! -d "$PFS_DIR/system/fonts" ] || [ -L "$PFS_DIR/system/fonts" ]; then
      printf '%s\n' "status=error" "code=recovery-failed" "message=The prior font overlay and its backup are unavailable; reinstall the module."
      exit 7
    fi
    if [ -f "$STATE_BACKUP" ] && [ ! -L "$STATE_BACKUP" ]; then
      mv -f "$STATE_BACKUP" "$PFS_STATE_FILE" || {
        printf '%s\n' "status=error" "code=recovery-failed" "message=Interrupted selection state could not be restored safely; reinstall the module."
        exit 7
      }
    elif [ "$RECOVERY_HAD_STATE" -eq 0 ]; then
      rm -f "$PFS_STATE_FILE"
    elif [ "$RECOVERY_COMMIT_INVALID" -eq 1 ]; then
      printf '%s\n' "status=error" "code=recovery-failed" "message=Committed selection state failed verification and its prior backup is unavailable; reinstall the module."
      exit 7
    elif [ ! -f "$PFS_STATE_FILE" ] || [ -L "$PFS_STATE_FILE" ]; then
      printf '%s\n' "status=error" "code=recovery-failed" "message=The prior selection state and its backup are unavailable; reinstall the module."
      exit 7
    fi
    sync || {
      printf '%s\n' "status=error" "code=recovery-durability-failed" "message=The restored overlay state could not be committed to storage; recovery data was preserved."
      exit 7
    }
    rm -rf "$STAGE_DIR"
    rm -f "$TRANSACTION_MARKER" "$TRANSACTION_TMP"
  fi
elif [ -e "$TRANSACTION_MARKER" ] || [ -L "$TRANSACTION_MARKER" ] \
  || [ -e "$BACKUP_DIR" ] || [ -L "$BACKUP_DIR" ] \
  || [ -e "$STATE_BACKUP" ] || [ -L "$STATE_BACKUP" ]; then
  printf '%s\n' "status=error" "code=unsafe-transaction-state" "message=Unexpected transaction data was preserved; reinstall the module before applying another font."
  exit 7
else
  rm -rf "$STAGE_DIR"
  if [ -e "$TRANSACTION_TMP" ] || [ -L "$TRANSACTION_TMP" ]; then
    [ -f "$TRANSACTION_TMP" ] && [ ! -L "$TRANSACTION_TMP" ] || {
      printf '%s\n' "status=error" "code=unsafe-transaction-state" "message=Unexpected transaction staging data was preserved; reinstall the module."
      exit 7
    }
    rm -f "$TRANSACTION_TMP"
  fi
fi

cleanup() {
  rm -rf "$STAGE_DIR"
  if [ "$COMMITTED" -eq 0 ] && [ "$MUTATION_STARTED" -eq 1 ]; then
    PFS_ROLLBACK_OK=1
    pfs_enable_skip_mount 2>/dev/null || PFS_ROLLBACK_OK=0
    if [ -d "$BACKUP_DIR" ] && [ ! -L "$BACKUP_DIR" ]; then
      rm -rf "$PFS_DIR/system/fonts" 2>/dev/null || PFS_ROLLBACK_OK=0
      mv "$BACKUP_DIR" "$PFS_DIR/system/fonts" 2>/dev/null || PFS_ROLLBACK_OK=0
    elif [ "$HAD_OVERLAY" -eq 0 ]; then
      rm -rf "$PFS_DIR/system/fonts" 2>/dev/null || PFS_ROLLBACK_OK=0
    fi
    if [ -f "$STATE_BACKUP" ] && [ ! -L "$STATE_BACKUP" ]; then
      mv -f "$STATE_BACKUP" "$PFS_STATE_FILE" 2>/dev/null || PFS_ROLLBACK_OK=0
    elif [ "$HAD_STATE" -eq 0 ]; then
      rm -f "$PFS_STATE_FILE" 2>/dev/null || true
    fi
    if [ "$PFS_ROLLBACK_OK" -eq 1 ]; then
      rm -rf "$BACKUP_DIR"
      rm -f "$STATE_BACKUP" "$TRANSACTION_MARKER" "$TRANSACTION_TMP"
    fi
  fi
  if [ "$COMMITTED" -eq 1 ] || [ "$MUTATION_STARTED" -eq 0 ]; then
    rm -rf "$BACKUP_DIR"
    rm -f "$STATE_BACKUP" "$TRANSACTION_MARKER" "$TRANSACTION_TMP"
  fi
  pfs_release_lock "$LOCK_DIR"
}
trap cleanup 0
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

mkdir -p "$STAGE_DIR/system/fonts"

if [ "$FONT_ID" != "system-default" ]; then
  if ! pfs_resolve_font "$FONT_ID"; then
    printf '%s\n' "status=error" "code=font-resolution-failed" "message=The selected font could not be resolved safely."
    exit 5
  fi

  if [ ! -f "$PFS_REGULAR_SOURCE" ] || [ ! -f "$PFS_BOLD_SOURCE" ]; then
    printf '%s\n' "status=error" "code=missing-font-asset" "message=The selected font assets are incomplete."
    exit 5
  fi

  if [ "$(sha256sum "$PFS_REGULAR_SOURCE" | awk '{print $1}')" != "$PFS_REGULAR_HASH" ] \
    || [ "$(sha256sum "$PFS_BOLD_SOURCE" | awk '{print $1}')" != "$PFS_BOLD_HASH" ]; then
    printf '%s\n' "status=error" "code=font-checksum-mismatch" "message=The selected font failed integrity validation."
    exit 5
  fi

  while IFS= read -r TARGET || [ -n "$TARGET" ]; do
    WEIGHT=$(pfs_target_weight "$TARGET")
    case "$WEIGHT" in
      regular) SOURCE="$PFS_REGULAR_SOURCE" ;;
      bold) SOURCE="$PFS_BOLD_SOURCE" ;;
      *) exit 5 ;;
    esac
    cp "$SOURCE" "$STAGE_DIR/system/fonts/$TARGET"
    chmod 0644 "$STAGE_DIR/system/fonts/$TARGET"
  done <"$PFS_TARGETS_FILE"
fi

# Everything needed for the new overlay is now staged and verified. Record the
# pre-transaction shape before creating skip_mount or moving any live payload.
if [ -e "$PFS_DIR/system/fonts" ] || [ -L "$PFS_DIR/system/fonts" ]; then
  if [ ! -d "$PFS_DIR/system/fonts" ] || [ -L "$PFS_DIR/system/fonts" ]; then
    printf '%s\n' "status=error" "code=unsafe-overlay-state" "message=The current module font overlay is not a safe directory; reinstall the module."
    exit 7
  fi
  HAD_OVERLAY=1
fi
if [ -f "$PFS_STATE_FILE" ] && [ ! -L "$PFS_STATE_FILE" ]; then
  HAD_STATE=1
fi
if ! write_transaction_marker prepared; then
  printf '%s\n' "status=error" "code=transaction-marker-failed" "message=The font transaction could not be recorded safely."
  exit 7
fi
if ! pfs_enable_skip_mount; then
  printf '%s\n' "status=error" "code=skip-mount-failed" "message=The module overlay could not be disabled before mutation."
  exit 7
fi
if ! sync; then
  printf '%s\n' "status=error" "code=durability-barrier-failed" "message=The fail-safe state could not be committed to storage; no overlay files were changed. Retry or reinstall before rebooting."
  exit 7
fi
MUTATION_STARTED=1

if [ "$HAD_STATE" -eq 1 ]; then
  cp "$PFS_STATE_FILE" "$STATE_BACKUP"
  chmod 0600 "$STATE_BACKUP"
fi

if [ "$HAD_OVERLAY" -eq 1 ]; then
  if ! mv "$PFS_DIR/system/fonts" "$BACKUP_DIR"; then
    printf '%s\n' "status=error" "code=overlay-backup-failed" "message=The working overlay could not be backed up; it was left in place."
    exit 7
  fi
fi

if [ "$FONT_ID" = "system-default" ]; then
  if ! rmdir "$STAGE_DIR/system/fonts"; then
    printf '%s\n' "status=error" "code=overlay-stage-failed" "message=The System Default transaction stage was not empty."
    exit 7
  fi
else
  if ! mv "$STAGE_DIR/system/fonts" "$PFS_DIR/system/fonts"; then
    printf '%s\n' "status=error" "code=overlay-install-failed" "message=The prepared font overlay could not be installed."
    exit 7
  fi
fi

if ! pfs_write_selection "$FONT_ID"; then
  printf '%s\n' "status=error" "code=state-write-failed" "message=Font state could not be saved; system overlay mounting remains safely disabled."
  exit 6
fi

if ! write_transaction_marker committed; then
  printf '%s\n' "status=error" "code=transaction-commit-failed" "message=The completed font transaction could not be recorded safely."
  exit 7
fi
if ! sync; then
  printf '%s\n' "status=error" "code=durability-barrier-failed" "message=The completed overlay could not be committed to storage; the previous selection was restored and mounting remains disabled."
  exit 7
fi
if [ "$FONT_ID" != "system-default" ]; then
  if ! rm -f "$PFS_DIR/skip_mount"; then
    printf '%s\n' "status=error" "code=overlay-enable-failed" "message=The completed font overlay could not be enabled."
    exit 7
  fi
fi
COMMITTED=1
rm -rf "$BACKUP_DIR"
rm -f "$STATE_BACKUP" "$TRANSACTION_MARKER" "$TRANSACTION_TMP"

printf '%s\n' \
  "status=ok" \
  "selected=$FONT_ID" \
  "config_backend=$PFS_CONFIG_BACKEND" \
  "recovered_stale_lock=$RECOVERED_STALE_LOCK" \
  "restart_required=true" \
  "message=Font selection staged successfully. Compare active and selected state to determine whether restart is required."
