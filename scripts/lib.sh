#!/system/bin/sh

PFS_MODULE_ID="persian_font_switcher"
PFS_SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PFS_DIR=${PFS_MODULE_DIR:-$(CDPATH= cd -- "$PFS_SCRIPT_DIR/.." && pwd)}
PFS_MANIFEST="$PFS_DIR/webroot/font-manifest.json"
PFS_STATE_DIR="$PFS_DIR/state"
PFS_STATE_FILE="$PFS_STATE_DIR/selected-font"
PFS_TARGETS_FILE="$PFS_STATE_DIR/supported-targets"
PFS_ADB_ROOT=${PFS_ADB_ROOT:-/data/adb}
PFS_DATA_DIR=${PFS_DATA_DIR:-"$PFS_ADB_ROOT/persian_font_switcher"}
PFS_CUSTOM_DIR="$PFS_DATA_DIR/custom-fonts"
PFS_STAGING_DIR="$PFS_DATA_DIR/staging"
PFS_KSUD="$PFS_ADB_ROOT/ksu/bin/ksud"

# Prints the root manager's BusyBox, if any.
pfs_busybox() {
  for PFS_BUSYBOX_PATH in "$PFS_ADB_ROOT/ksu/bin/busybox" "$PFS_ADB_ROOT/magisk/busybox" \
    "$PFS_ADB_ROOT/ap/bin/busybox"; do
    [ -x "$PFS_BUSYBOX_PATH" ] && { printf '%s\n' "$PFS_BUSYBOX_PATH"; return 0; }
  done
  return 1
}

# Module scripts run under BusyBox ash in standalone mode, as boot scripts do.
# The WebUI starts them under mksh, which makes descriptors opened by `exec`
# close-on-exec, so an external flock never sees the lock descriptor.
case "$0" in
  */scripts/*.sh)
    if [ "${ASH_STANDALONE:-}" != 1 ] && PFS_REEXEC_BUSYBOX=$(pfs_busybox); then
      ASH_STANDALONE=1
      export ASH_STANDALONE
      exec "$PFS_REEXEC_BUSYBOX" sh "$0" "$@"
    fi
    ;;
esac

pfs_valid_id() {
  PFS_CHECK_ID="$1"
  [ -n "$PFS_CHECK_ID" ] || return 1
  [ "${#PFS_CHECK_ID}" -le 32 ] || return 1
  case "$PFS_CHECK_ID" in
    *[!a-z0-9_-]*|-*|_*) return 1 ;;
  esac
  return 0
}

pfs_manifest_record() {
  PFS_LOOKUP_ID="$1"
  awk -v needle="\"id\": \"$PFS_LOOKUP_ID\"" 'index($0, needle) { print; exit }' "$PFS_MANIFEST"
}

pfs_custom_dir() {
  PFS_CUSTOM_ID="$1"
  pfs_valid_id "$PFS_CUSTOM_ID" || return 1
  [ "${#PFS_CUSTOM_ID}" -eq 31 ] || return 1
  case "$PFS_CUSTOM_ID" in custom-[0-9a-f]*) ;; *) return 1 ;; esac
  PFS_CUSTOM_SUFFIX=${PFS_CUSTOM_ID#custom-}
  [ "${#PFS_CUSTOM_SUFFIX}" -eq 24 ] || return 1
  case "$PFS_CUSTOM_SUFFIX" in *[!0-9a-f]*) return 1 ;; esac
  printf '%s\n' "$PFS_CUSTOM_DIR/$PFS_CUSTOM_ID"
}

pfs_custom_storage_safe() {
  for PFS_STORAGE_ROOT in "$PFS_DATA_DIR" "$PFS_CUSTOM_DIR"; do
    if [ -e "$PFS_STORAGE_ROOT" ] || [ -L "$PFS_STORAGE_ROOT" ]; then
      [ -d "$PFS_STORAGE_ROOT" ] && [ ! -L "$PFS_STORAGE_ROOT" ] || return 1
    fi
  done
  return 0
}

# Complete or abort the one fixed custom-font deletion transaction. Callers
# must hold the shared operation flock before invoking this helper.
pfs_recover_delete_transaction() {
  PFS_DELETE_MARKER="$PFS_DATA_DIR/.delete-transaction"
  PFS_DELETE_MARKER_TMP="$PFS_DATA_DIR/.delete-transaction.new"
  PFS_DELETE_TRASH="$PFS_DATA_DIR/.deleted-custom-font"
  PFS_DELETE_RECOVERED=0
  pfs_custom_storage_safe || return 1

  if [ -e "$PFS_DELETE_MARKER_TMP" ] || [ -L "$PFS_DELETE_MARKER_TMP" ]; then
    [ -f "$PFS_DELETE_MARKER_TMP" ] && [ ! -L "$PFS_DELETE_MARKER_TMP" ] || return 1
    rm -f "$PFS_DELETE_MARKER_TMP" || return 1
    PFS_DELETE_RECOVERED=1
  fi

  if [ -e "$PFS_DELETE_MARKER" ] || [ -L "$PFS_DELETE_MARKER" ]; then
    [ -f "$PFS_DELETE_MARKER" ] && [ ! -L "$PFS_DELETE_MARKER" ] || return 1
    IFS= read -r PFS_DELETE_ID <"$PFS_DELETE_MARKER" 2>/dev/null || return 1
    PFS_DELETE_PATH=$(pfs_custom_dir "$PFS_DELETE_ID") || return 1
    if [ -e "$PFS_DELETE_TRASH" ] || [ -L "$PFS_DELETE_TRASH" ]; then
      [ -d "$PFS_DELETE_TRASH" ] && [ ! -L "$PFS_DELETE_TRASH" ] || return 1
      [ ! -e "$PFS_DELETE_PATH" ] && [ ! -L "$PFS_DELETE_PATH" ] || return 1
      rm -rf "$PFS_DELETE_TRASH" || return 1
    fi
    # When the canonical path remains, power was lost before the atomic move;
    # removing the marker aborts that uncommitted deletion without data loss.
    rm -f "$PFS_DELETE_MARKER" || return 1
    PFS_DELETE_RECOVERED=1
  elif [ -e "$PFS_DELETE_TRASH" ] || [ -L "$PFS_DELETE_TRASH" ]; then
    # A trash path without its durable marker has no safely provable owner.
    return 1
  fi
  return 0
}

pfs_read_hash_file() {
  PFS_HASH_FILE="$1"
  [ -f "$PFS_HASH_FILE" ] && [ ! -L "$PFS_HASH_FILE" ] || return 1
  IFS= read -r PFS_STORED_HASH <"$PFS_HASH_FILE" || return 1
  [ "${#PFS_STORED_HASH}" -eq 64 ] || return 1
  case "$PFS_STORED_HASH" in *[!0-9a-f]*) return 1 ;; esac
  printf '%s\n' "$PFS_STORED_HASH"
}

pfs_custom_font_file_valid() {
  PFS_FONT_FILE="$1"
  [ -f "$PFS_FONT_FILE" ] && [ ! -L "$PFS_FONT_FILE" ] || return 1
  PFS_FONT_SIZE=$(wc -c <"$PFS_FONT_FILE" 2>/dev/null | tr -d ' ') || return 1
  [ "$PFS_FONT_SIZE" -ge 256 ] && [ "$PFS_FONT_SIZE" -le 16777216 ] || return 1
  PFS_FONT_MAGIC=$(od -An -tx1 -N4 "$PFS_FONT_FILE" 2>/dev/null | tr -d ' \n') || return 1
  case "$PFS_FONT_MAGIC" in 00010000|4f54544f) return 0 ;; *) return 1 ;; esac
}

pfs_custom_name_valid() {
  PFS_NAME_FILE="$1"
  [ -s "$PFS_NAME_FILE" ] && [ ! -L "$PFS_NAME_FILE" ] || return 1
  PFS_NAME_B64=$(tr -d '\n' <"$PFS_NAME_FILE" 2>/dev/null) || return 1
  [ -n "$PFS_NAME_B64" ] && [ "${#PFS_NAME_B64}" -le 256 ] || return 1
  case "$PFS_NAME_B64" in *[!A-Za-z0-9+/=]*) return 1 ;; esac
  PFS_NAME_SIZE=$(printf '%s' "$PFS_NAME_B64" | base64 -d 2>/dev/null | wc -c | tr -d ' ') || return 1
  [ "$PFS_NAME_SIZE" -ge 1 ] && [ "$PFS_NAME_SIZE" -le 80 ] || return 1
  if printf '%s' "$PFS_NAME_B64" | base64 -d 2>/dev/null | LC_ALL=C grep -q '[[:cntrl:]]'; then
    return 1
  fi
  printf '%s' "$PFS_NAME_B64" | base64 -d >/dev/null 2>&1
}

pfs_custom_valid() {
  PFS_CUSTOM_CHECK_ID="$1"
  pfs_custom_storage_safe || return 1
  PFS_CUSTOM_CHECK_DIR=$(pfs_custom_dir "$PFS_CUSTOM_CHECK_ID") || return 1
  [ ! -L "$PFS_CUSTOM_CHECK_DIR" ] || return 1
  pfs_custom_font_file_valid "$PFS_CUSTOM_CHECK_DIR/regular.ttf" \
    && pfs_custom_font_file_valid "$PFS_CUSTOM_CHECK_DIR/bold.ttf" \
    && pfs_custom_name_valid "$PFS_CUSTOM_CHECK_DIR/name.b64" || return 1
  [ ! -L "$PFS_CUSTOM_CHECK_DIR/regular.sha256" ] \
    && [ ! -L "$PFS_CUSTOM_CHECK_DIR/bold.sha256" ] || return 1
  PFS_CUSTOM_REGULAR_HASH=$(pfs_read_hash_file "$PFS_CUSTOM_CHECK_DIR/regular.sha256") || return 1
  PFS_CUSTOM_BOLD_HASH=$(pfs_read_hash_file "$PFS_CUSTOM_CHECK_DIR/bold.sha256") || return 1
  [ "$(sha256sum "$PFS_CUSTOM_CHECK_DIR/regular.ttf" | awk '{print $1}')" = "$PFS_CUSTOM_REGULAR_HASH" ] \
    && [ "$(sha256sum "$PFS_CUSTOM_CHECK_DIR/bold.ttf" | awk '{print $1}')" = "$PFS_CUSTOM_BOLD_HASH" ] || return 1
  PFS_EXPECTED_CUSTOM_ID="custom-$(printf '%s' "$PFS_CUSTOM_REGULAR_HASH" | cut -c1-12)$(printf '%s' "$PFS_CUSTOM_BOLD_HASH" | cut -c1-12)"
  [ "$PFS_CUSTOM_CHECK_ID" = "$PFS_EXPECTED_CUSTOM_ID" ]
}

pfs_json_field() {
  PFS_RECORD="$1"
  PFS_FIELD="$2"
  printf '%s\n' "$PFS_RECORD" | sed -n "s/.*\"$PFS_FIELD\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p"
}

pfs_valid_selection() {
  PFS_SELECTION="$1"
  pfs_valid_id "$PFS_SELECTION" || return 1
  [ "$PFS_SELECTION" = "system-default" ] && return 0
  [ -n "$(pfs_manifest_record "$PFS_SELECTION")" ] && return 0
  pfs_custom_valid "$PFS_SELECTION"
}

pfs_resolve_font() {
  PFS_RESOLVE_ID="$1"
  PFS_RESOLVE_RECORD=$(pfs_manifest_record "$PFS_RESOLVE_ID")
  if [ -n "$PFS_RESOLVE_RECORD" ]; then
    PFS_REGULAR_REL=$(pfs_json_field "$PFS_RESOLVE_RECORD" regular)
    PFS_BOLD_REL=$(pfs_json_field "$PFS_RESOLVE_RECORD" bold)
    [ "$PFS_REGULAR_REL" = "assets/fonts/$PFS_RESOLVE_ID/regular.ttf" ] \
      && [ "$PFS_BOLD_REL" = "assets/fonts/$PFS_RESOLVE_ID/bold.ttf" ] || return 1
    PFS_REGULAR_SOURCE="$PFS_DIR/$PFS_REGULAR_REL"
    PFS_BOLD_SOURCE="$PFS_DIR/$PFS_BOLD_REL"
    PFS_REGULAR_HASH=$(pfs_json_field "$PFS_RESOLVE_RECORD" sha256Regular)
    PFS_BOLD_HASH=$(pfs_json_field "$PFS_RESOLVE_RECORD" sha256Bold)
    return 0
  fi

  pfs_custom_valid "$PFS_RESOLVE_ID" || return 1
  PFS_RESOLVE_CUSTOM_DIR=$(pfs_custom_dir "$PFS_RESOLVE_ID") || return 1
  PFS_REGULAR_SOURCE="$PFS_RESOLVE_CUSTOM_DIR/regular.ttf"
  PFS_BOLD_SOURCE="$PFS_RESOLVE_CUSTOM_DIR/bold.ttf"
  PFS_REGULAR_HASH=$(pfs_read_hash_file "$PFS_RESOLVE_CUSTOM_DIR/regular.sha256") || return 1
  PFS_BOLD_HASH=$(pfs_read_hash_file "$PFS_RESOLVE_CUSTOM_DIR/bold.sha256") || return 1
}

pfs_allowed_target() {
  case "$1" in
    NotoNaskhArabicUI-Regular.ttf|NotoNaskhArabicUI-Bold.ttf|NotoNaskhArabic-Regular.ttf|NotoNaskhArabic-Bold.ttf) return 0 ;;
    *) return 1 ;;
  esac
}

pfs_target_weight() {
  case "$1" in
    *-Bold.ttf) printf '%s\n' bold ;;
    *-Regular.ttf) printf '%s\n' regular ;;
    *) return 1 ;;
  esac
}

pfs_acquire_lock() {
  PFS_ACQUIRE_FILE="$1"
  PFS_LOCK_ERROR=unavailable
  PFS_LOCK_RECOVERED=0
  [ -z "${PFS_HELD_LOCK:-}" ] || { PFS_LOCK_ERROR=busy; return 1; }
  command -v flock >/dev/null 2>&1 || return 1

  # Migrate only an owner-identified, dead directory lock from pre-flock
  # releases. An empty legacy apply lock is indistinguishable from a live rc4
  # operation and therefore fails closed until reinstall/update removes it.
  if [ -d "$PFS_ACQUIRE_FILE" ] && [ ! -L "$PFS_ACQUIRE_FILE" ]; then
    PFS_LEGACY_PID=""
    if [ -f "$PFS_ACQUIRE_FILE/pid" ] && [ ! -L "$PFS_ACQUIRE_FILE/pid" ]; then
      IFS= read -r PFS_LEGACY_PID <"$PFS_ACQUIRE_FILE/pid" 2>/dev/null || PFS_LEGACY_PID=""
    fi
    case "$PFS_LEGACY_PID" in *[!0-9]*|'') PFS_LOCK_ERROR=busy; return 1 ;; esac
    if kill -0 "$PFS_LEGACY_PID" 2>/dev/null; then
      PFS_LOCK_ERROR=busy
      return 1
    fi
    for PFS_LEGACY_META in pid boot-id start-time; do
      [ ! -L "$PFS_ACQUIRE_FILE/$PFS_LEGACY_META" ] || return 1
      rm -f "$PFS_ACQUIRE_FILE/$PFS_LEGACY_META" 2>/dev/null || return 1
    done
    if rmdir "$PFS_ACQUIRE_FILE" 2>/dev/null; then
      PFS_LOCK_RECOVERED=1
    elif [ ! -f "$PFS_ACQUIRE_FILE" ] || [ -L "$PFS_ACQUIRE_FILE" ]; then
      return 1
    fi
  fi

  if [ -e "$PFS_ACQUIRE_FILE" ] || [ -L "$PFS_ACQUIRE_FILE" ]; then
    [ -f "$PFS_ACQUIRE_FILE" ] && [ ! -L "$PFS_ACQUIRE_FILE" ] || return 1
  fi
  if ! exec 9>>"$PFS_ACQUIRE_FILE"; then
    return 1
  fi
  if ! flock -n 9; then
    exec 9>&-
    PFS_LOCK_ERROR=busy
    return 1
  fi
  if ! chmod 0600 "$PFS_ACQUIRE_FILE"; then
    flock -u 9 2>/dev/null || true
    exec 9>&-
    return 1
  fi
  PFS_HELD_LOCK="$PFS_ACQUIRE_FILE"
  PFS_LOCK_ERROR=""
  return 0
}

pfs_release_lock() {
  PFS_RELEASE_FILE="$1"
  [ "${PFS_HELD_LOCK:-}" = "$PFS_RELEASE_FILE" ] || return 0
  flock -u 9 2>/dev/null || true
  exec 9>&-
  PFS_HELD_LOCK=""
  return 0
}

pfs_validate_targets() {
  [ -s "$PFS_TARGETS_FILE" ] || return 1
  PFS_TARGET_COUNT=0
  PFS_SEEN_UI_REGULAR=0
  PFS_SEEN_UI_BOLD=0
  PFS_SEEN_REGULAR=0
  PFS_SEEN_BOLD=0
  while IFS= read -r PFS_TARGET || [ -n "$PFS_TARGET" ]; do
    pfs_allowed_target "$PFS_TARGET" || return 1
    case "$PFS_TARGET" in
      NotoNaskhArabicUI-Regular.ttf) [ "$PFS_SEEN_UI_REGULAR" -eq 0 ] || return 1; PFS_SEEN_UI_REGULAR=1 ;;
      NotoNaskhArabicUI-Bold.ttf) [ "$PFS_SEEN_UI_BOLD" -eq 0 ] || return 1; PFS_SEEN_UI_BOLD=1 ;;
      NotoNaskhArabic-Regular.ttf) [ "$PFS_SEEN_REGULAR" -eq 0 ] || return 1; PFS_SEEN_REGULAR=1 ;;
      NotoNaskhArabic-Bold.ttf) [ "$PFS_SEEN_BOLD" -eq 0 ] || return 1; PFS_SEEN_BOLD=1 ;;
    esac
    PFS_TARGET_COUNT=$((PFS_TARGET_COUNT + 1))
  done <"$PFS_TARGETS_FILE"
  [ "$PFS_TARGET_COUNT" -eq 4 ] \
    && [ "$PFS_SEEN_UI_REGULAR" -eq 1 ] \
    && [ "$PFS_SEEN_UI_BOLD" -eq 1 ] \
    && [ "$PFS_SEEN_REGULAR" -eq 1 ] \
    && [ "$PFS_SEEN_BOLD" -eq 1 ]
}

pfs_read_selection() {
  # The module file is written atomically and is authoritative at runtime.
  # KernelSU config is a cross-update fallback only; it may be stale if a
  # best-effort config write failed after the module state commit.
  if [ -f "$PFS_STATE_FILE" ]; then
    IFS= read -r PFS_FILE_SELECTION <"$PFS_STATE_FILE" || true
    if pfs_valid_selection "$PFS_FILE_SELECTION"; then
      printf '%s\n' "$PFS_FILE_SELECTION"
      return 0
    fi
  fi

  if [ -x "$PFS_KSUD" ]; then
    PFS_CONFIG_SELECTION=$(KSU_MODULE="$PFS_MODULE_ID" "$PFS_KSUD" module config get selected_font 2>/dev/null || true)
    if pfs_valid_selection "$PFS_CONFIG_SELECTION"; then
      printf '%s\n' "$PFS_CONFIG_SELECTION"
      return 0
    fi
  fi

  printf '%s\n' system-default
}

pfs_write_selection() {
  PFS_NEW_SELECTION="$1"
  [ ! -L "$PFS_STATE_DIR" ] || return 1
  mkdir -p "$PFS_STATE_DIR" || return 1
  [ -d "$PFS_STATE_DIR" ] || return 1
  [ ! -L "$PFS_STATE_FILE" ] && [ ! -d "$PFS_STATE_FILE" ] || return 1
  PFS_STATE_TMP="$PFS_STATE_FILE.tmp.$$"
  printf '%s\n' "$PFS_NEW_SELECTION" >"$PFS_STATE_TMP" || return 1
  chmod 0600 "$PFS_STATE_TMP" || { rm -f "$PFS_STATE_TMP"; return 1; }
  mv -f "$PFS_STATE_TMP" "$PFS_STATE_FILE" || { rm -f "$PFS_STATE_TMP"; return 1; }
  PFS_CONFIG_BACKEND="module-file"

  if [ "${PFS_SKIP_KSU_CONFIG:-0}" != "1" ] && [ -x "$PFS_KSUD" ]; then
    if KSU_MODULE="$PFS_MODULE_ID" "$PFS_KSUD" module config set selected_font "$PFS_NEW_SELECTION" >/dev/null 2>&1; then
      PFS_CONFIG_BACKEND="kernelsu-config"
    fi
  fi
  return 0
}

# ---------------------------------------------------------------------------
# Mount-free activation (0.3.0+)
#
# Android 12+ apps do not parse fonts.xml for the system font map. system_server's
# FontManagerService serializes font file *paths* into shared memory and every
# app opens those paths lazily inside its own mount namespace. The module stores
# the selected font under a real /data/fonts path that every app domain may
# already read (font_data_file, the label of Android's updatable fonts) and
# bind-mounts a patched copy of the ROM's font XML only inside system_server's
# mount namespace. That namespace is a one-way slave of init, so the bind is
# never visible to init, zygote, or any app, independent of KernelSU/NeoZygisk
# module-unmount settings. No file under system/ is shipped or mounted.
#
# Layout (generations are immutable once published):
#   $PFS_FONT_ROOT/gen/<N>/<four stock-named copies>
#   $PFS_FONT_ROOT/xml/<N>/{font_fallback.xml,fonts.xml}
#   $PFS_FONT_ROOT/generation          last published generation
# ---------------------------------------------------------------------------
PFS_FONT_ROOT=${PFS_FONT_ROOT:-/data/fonts/persian_font_switcher}
PFS_RUNTIME_DIR=${PFS_RUNTIME_DIR:-"$PFS_DIR/runtime"}
PFS_REDIRECT_STATE="$PFS_RUNTIME_DIR/redirect.state"
PFS_GUARD_FILE="$PFS_STATE_DIR/boot-guard"
PFS_GUARD_LIMIT=2
PFS_XML_NAMES="font_fallback.xml fonts.xml"
PFS_TARGET_NAMES="NotoNaskhArabicUI-Regular.ttf NotoNaskhArabicUI-Bold.ttf NotoNaskhArabic-Regular.ttf NotoNaskhArabic-Bold.ttf"
PFS_FONT_LABEL=u:object_r:font_data_file:s0
PFS_PROC_ROOT=${PFS_PROC_ROOT:-/proc}
PFS_TRUST_AGE=${PFS_TRUST_AGE:-3}
PFS_CHCON_BIN=${PFS_CHCON_BIN:-chcon}
PFS_CHOWN_BIN=${PFS_CHOWN_BIN:-chown}
PFS_NSENTER_BIN=${PFS_NSENTER_BIN:-nsenter}
PFS_PIDOF_BIN=${PFS_PIDOF_BIN:-pidof}
PFS_SERVICE_BIN=${PFS_SERVICE_BIN:-service}
PFS_CMD_BIN=${PFS_CMD_BIN:-cmd}
PFS_AM_BIN=${PFS_AM_BIN:-am}
PFS_DUMPSYS_BIN=${PFS_DUMPSYS_BIN:-dumpsys}
PFS_GETPROP_BIN=${PFS_GETPROP_BIN:-getprop}
PFS_LOG_BIN=${PFS_LOG_BIN:-log}
PFS_KILL_BIN=${PFS_KILL_BIN:-kill}

pfs_log() {
  "$PFS_LOG_BIN" -t PersianFontSwitcher "$*" >/dev/null 2>&1 || true
  if [ -d "$PFS_RUNTIME_DIR" ] && [ ! -L "$PFS_RUNTIME_DIR" ]; then
    printf '%s %s\n' "$(pfs_uptime)" "$*" >>"$PFS_RUNTIME_DIR/events.log" 2>/dev/null || true
  fi
}

pfs_uptime() {
  PFS_UPTIME_VALUE=$(cut -d' ' -f1 "$PFS_PROC_ROOT/uptime" 2>/dev/null) || PFS_UPTIME_VALUE=0
  printf '%s\n' "${PFS_UPTIME_VALUE:-0}"
}

pfs_uptime_seconds() {
  PFS_UPTIME_WHOLE=$(pfs_uptime)
  PFS_UPTIME_WHOLE=${PFS_UPTIME_WHOLE%%.*}
  case "$PFS_UPTIME_WHOLE" in ''|*[!0-9]*) PFS_UPTIME_WHOLE=0 ;; esac
  printf '%s\n' "$PFS_UPTIME_WHOLE"
}

# Seconds since the given process started, or nothing when unknown.
pfs_process_age() {
  PFS_START_TICKS=$(sed 's/^.*) //' "$PFS_PROC_ROOT/$1/stat" 2>/dev/null | awk '{print $20}')
  case "$PFS_START_TICKS" in ''|*[!0-9]*) return 1 ;; esac
  awk -v up="$(pfs_uptime)" -v start="$PFS_START_TICKS" 'BEGIN { printf "%d\n", up - start / 100 }'
}

pfs_boot_completed() {
  [ "$("$PFS_GETPROP_BIN" sys.boot_completed 2>/dev/null)" = 1 ]
}

pfs_ensure_runtime_dir() {
  [ ! -L "$PFS_RUNTIME_DIR" ] || return 1
  mkdir -p "$PFS_RUNTIME_DIR" || return 1
  chmod 0700 "$PFS_RUNTIME_DIR" || return 1
}

# Atomically replaces the runtime state record with the given key=value lines.
pfs_write_state() {
  pfs_ensure_runtime_dir || return 1
  PFS_STATE_RECORD_TMP="$PFS_REDIRECT_STATE.tmp.$$"
  printf '%s\n' "$@" >"$PFS_STATE_RECORD_TMP" || return 1
  chmod 0600 "$PFS_STATE_RECORD_TMP" || { rm -f "$PFS_STATE_RECORD_TMP"; return 1; }
  mv -f "$PFS_STATE_RECORD_TMP" "$PFS_REDIRECT_STATE" || { rm -f "$PFS_STATE_RECORD_TMP"; return 1; }
}

pfs_state_get() {
  [ -f "$PFS_REDIRECT_STATE" ] && [ ! -L "$PFS_REDIRECT_STATE" ] || return 1
  sed -n "s/^$1=//p" "$PFS_REDIRECT_STATE" | sed -n '1p'
}

# Merges key=value pairs into the current redirect record.
pfs_update_state() {
  [ -f "$PFS_REDIRECT_STATE" ] && [ ! -L "$PFS_REDIRECT_STATE" ] || return 1
  PFS_STATE_RECORD_TMP="$PFS_REDIRECT_STATE.tmp.$$"
  {
    awk -v keys="$(printf '%s\n' "$@" | sed 's/=.*//' | tr '\n' ' ')" '
      BEGIN { n = split(keys, k, " "); for (i = 1; i <= n; i++) drop[k[i]] = 1 }
      { key = $0; sub(/=.*/, "", key); if (!(key in drop)) print }' "$PFS_REDIRECT_STATE"
    printf '%s\n' "$@"
  } >"$PFS_STATE_RECORD_TMP" || { rm -f "$PFS_STATE_RECORD_TMP"; return 1; }
  chmod 0600 "$PFS_STATE_RECORD_TMP" || { rm -f "$PFS_STATE_RECORD_TMP"; return 1; }
  mv -f "$PFS_STATE_RECORD_TMP" "$PFS_REDIRECT_STATE" || { rm -f "$PFS_STATE_RECORD_TMP"; return 1; }
}

# Takes the shared operation lock, waiting up to the given number of seconds.
pfs_wait_lock() {
  PFS_WAIT_LIMIT=$2
  PFS_WAITED=0
  while ! pfs_acquire_lock "$1"; do
    [ "${PFS_LOCK_ERROR:-}" = busy ] || return 1
    PFS_WAITED=$((PFS_WAITED + 1))
    [ "$PFS_WAITED" -le "$PFS_WAIT_LIMIT" ] || return 1
    sleep 1
  done
}

# Applies the mode, system ownership, and font_data_file label that Android's
# updatable-font directory uses, so every app domain can read the result.
pfs_secure_font_path() {
  chmod "$2" "$1" || return 1
  "$PFS_CHOWN_BIN" 1000:1000 "$1" || return 1
  "$PFS_CHCON_BIN" "$PFS_FONT_LABEL" "$1" || return 1
}

pfs_font_root_parent_ready() {
  PFS_FONT_PARENT=${PFS_FONT_ROOT%/*}
  [ -n "$PFS_FONT_PARENT" ] && [ -d "$PFS_FONT_PARENT" ] && [ ! -L "$PFS_FONT_PARENT" ]
}

pfs_ensure_font_dirs() {
  pfs_font_root_parent_ready || return 1
  for PFS_FONT_SUBDIR in "$PFS_FONT_ROOT" "$PFS_FONT_ROOT/gen" "$PFS_FONT_ROOT/xml"; do
    [ ! -L "$PFS_FONT_SUBDIR" ] || return 1
    if [ -e "$PFS_FONT_SUBDIR" ] && [ ! -d "$PFS_FONT_SUBDIR" ]; then
      return 1
    fi
    mkdir -p "$PFS_FONT_SUBDIR" || return 1
    pfs_secure_font_path "$PFS_FONT_SUBDIR" 0711 || return 1
  done
}

pfs_current_generation() {
  PFS_GENERATION_FILE="$PFS_FONT_ROOT/generation"
  [ -f "$PFS_GENERATION_FILE" ] && [ ! -L "$PFS_GENERATION_FILE" ] || return 1
  IFS= read -r PFS_GENERATION_VALUE <"$PFS_GENERATION_FILE" || return 1
  case "$PFS_GENERATION_VALUE" in ''|*[!0-9]*|0*) return 1 ;; esac
  [ "${#PFS_GENERATION_VALUE}" -le 6 ] || return 1
  printf '%s\n' "$PFS_GENERATION_VALUE"
}

pfs_highest_generation() {
  PFS_HIGHEST=0
  for PFS_HIGHEST_PATH in "$PFS_FONT_ROOT/gen"/* "$PFS_FONT_ROOT/xml"/*; do
    PFS_HIGHEST_NAME=${PFS_HIGHEST_PATH##*/}
    case "$PFS_HIGHEST_NAME" in ''|*[!0-9]*|0*) continue ;; esac
    [ "${#PFS_HIGHEST_NAME}" -le 6 ] || continue
    [ "$PFS_HIGHEST_NAME" -gt "$PFS_HIGHEST" ] && PFS_HIGHEST=$PFS_HIGHEST_NAME
  done
  printf '%s\n' "$PFS_HIGHEST"
}

pfs_target_hash() {
  case "$(pfs_target_weight "$1")" in
    regular) printf '%s\n' "$PFS_REGULAR_HASH" ;;
    bold) printf '%s\n' "$PFS_BOLD_HASH" ;;
    *) return 1 ;;
  esac
}

# True when a staged generation holds exactly the four verified copies of the
# font most recently resolved by pfs_resolve_font.
pfs_generation_matches() {
  PFS_MATCH_DIR="$PFS_FONT_ROOT/gen/$1"
  [ -d "$PFS_MATCH_DIR" ] && [ ! -L "$PFS_MATCH_DIR" ] || return 1
  for PFS_MATCH_TARGET in $PFS_TARGET_NAMES; do
    PFS_MATCH_FILE="$PFS_MATCH_DIR/$PFS_MATCH_TARGET"
    [ -f "$PFS_MATCH_FILE" ] && [ ! -L "$PFS_MATCH_FILE" ] || return 1
    PFS_MATCH_EXPECTED=$(pfs_target_hash "$PFS_MATCH_TARGET") || return 1
    [ "$(sha256sum "$PFS_MATCH_FILE" | awk '{print $1}')" = "$PFS_MATCH_EXPECTED" ] || return 1
  done
}

pfs_relabel_generation() {
  pfs_secure_font_path "$PFS_FONT_ROOT/gen/$1" 0711 || return 1
  for PFS_RELABEL_TARGET in $PFS_TARGET_NAMES; do
    pfs_secure_font_path "$PFS_FONT_ROOT/gen/$1/$PFS_RELABEL_TARGET" 0644 || return 1
  done
}

# Copies the resolved font into a new, unpublished generation directory and
# sets PFS_GENERATION. Published generations are never rewritten, because
# running apps may still lazily open them.
pfs_stage_new_generation() {
  PFS_GENERATION=""
  PFS_CURRENT_GENERATION=$(pfs_current_generation 2>/dev/null) || PFS_CURRENT_GENERATION=0
  PFS_HIGHEST_GENERATION=$(pfs_highest_generation)
  PFS_NEW_GENERATION=$PFS_CURRENT_GENERATION
  [ "$PFS_HIGHEST_GENERATION" -gt "$PFS_NEW_GENERATION" ] && PFS_NEW_GENERATION=$PFS_HIGHEST_GENERATION
  PFS_NEW_GENERATION=$((PFS_NEW_GENERATION + 1))
  PFS_GENERATION_STAGE="$PFS_FONT_ROOT/gen/.stage.$$"
  rm -rf "$PFS_GENERATION_STAGE" || return 1
  mkdir "$PFS_GENERATION_STAGE" || return 1
  for PFS_STAGE_TARGET in $PFS_TARGET_NAMES; do
    case "$(pfs_target_weight "$PFS_STAGE_TARGET")" in
      regular) PFS_STAGE_SOURCE="$PFS_REGULAR_SOURCE" ;;
      bold) PFS_STAGE_SOURCE="$PFS_BOLD_SOURCE" ;;
      *) rm -rf "$PFS_GENERATION_STAGE"; return 1 ;;
    esac
    cp "$PFS_STAGE_SOURCE" "$PFS_GENERATION_STAGE/$PFS_STAGE_TARGET" \
      && pfs_secure_font_path "$PFS_GENERATION_STAGE/$PFS_STAGE_TARGET" 0644 \
      || { rm -rf "$PFS_GENERATION_STAGE"; return 1; }
  done
  pfs_secure_font_path "$PFS_GENERATION_STAGE" 0711 || { rm -rf "$PFS_GENERATION_STAGE"; return 1; }
  mv "$PFS_GENERATION_STAGE" "$PFS_FONT_ROOT/gen/$PFS_NEW_GENERATION" \
    || { rm -rf "$PFS_GENERATION_STAGE"; return 1; }
  pfs_generation_matches "$PFS_NEW_GENERATION" || return 1
  PFS_GENERATION=$PFS_NEW_GENERATION
}

pfs_publish_generation() {
  PFS_GENERATION_TMP="$PFS_FONT_ROOT/.generation.tmp.$$"
  printf '%s\n' "$1" >"$PFS_GENERATION_TMP" || return 1
  chmod 0600 "$PFS_GENERATION_TMP" || { rm -f "$PFS_GENERATION_TMP"; return 1; }
  mv -f "$PFS_GENERATION_TMP" "$PFS_FONT_ROOT/generation" || { rm -f "$PFS_GENERATION_TMP"; return 1; }
}

pfs_rom_xml_path() {
  printf '%s\n' "${PFS_TEST_SYSTEM_ROOT:-/system}/etc/$1"
}

pfs_count_matches() {
  grep -o "$1" "$2" 2>/dev/null | wc -l | tr -d ' '
}

# Writes a copy of a pristine ROM font XML in which only the four Arabic
# fallback file names resolve, relative to /system/fonts/, to the given
# generation. The literal ".ttf"-suffixed names never match the postScriptName
# attributes, and no target name is a substring of another.
pfs_patch_xml() {
  PFS_XML_SOURCE="$1"
  PFS_XML_DEST="$2"
  PFS_XML_GENERATION="$3"
  PFS_XML_REL="../..$PFS_FONT_ROOT/gen/$PFS_XML_GENERATION"
  case "$PFS_XML_REL" in *[!A-Za-z0-9._/-]*) return 1 ;; esac
  [ -f "$PFS_XML_SOURCE" ] || return 1
  grep -q '</familyset>' "$PFS_XML_SOURCE" || return 1
  # A pristine ROM file never contains a relative parent reference; refusing it
  # prevents patching an already redirected view.
  if grep -q '\.\./\.\./' "$PFS_XML_SOURCE"; then
    return 1
  fi
  sed \
    -e "s|NotoNaskhArabicUI-Regular\.ttf|$PFS_XML_REL/NotoNaskhArabicUI-Regular.ttf|g" \
    -e "s|NotoNaskhArabicUI-Bold\.ttf|$PFS_XML_REL/NotoNaskhArabicUI-Bold.ttf|g" \
    -e "s|NotoNaskhArabic-Regular\.ttf|$PFS_XML_REL/NotoNaskhArabic-Regular.ttf|g" \
    -e "s|NotoNaskhArabic-Bold\.ttf|$PFS_XML_REL/NotoNaskhArabic-Bold.ttf|g" \
    "$PFS_XML_SOURCE" >"$PFS_XML_DEST" || return 1
  for PFS_XML_TARGET in $PFS_TARGET_NAMES; do
    PFS_XML_PATTERN=$(printf '%s' "$PFS_XML_TARGET" | sed 's/\./\\./g')
    PFS_XML_BEFORE=$(pfs_count_matches "$PFS_XML_PATTERN" "$PFS_XML_SOURCE")
    PFS_XML_AFTER=$(pfs_count_matches "gen/$PFS_XML_GENERATION/$PFS_XML_PATTERN" "$PFS_XML_DEST")
    PFS_XML_TOTAL=$(pfs_count_matches "$PFS_XML_PATTERN" "$PFS_XML_DEST")
    if [ "$PFS_XML_BEFORE" -lt 1 ] || [ "$PFS_XML_AFTER" -ne "$PFS_XML_BEFORE" ] \
      || [ "$PFS_XML_TOTAL" -ne "$PFS_XML_BEFORE" ]; then
      return 1
    fi
  done
  grep -q '</familyset>' "$PFS_XML_DEST" || return 1
  pfs_secure_font_path "$PFS_XML_DEST" 0640
}

# Builds xml/<N>/ for every font XML the ROM ships, in a staging directory that
# is renamed into place only after every file patched exactly. Fails closed.
pfs_build_xml() {
  PFS_XML_STAGE="$PFS_FONT_ROOT/xml/.stage.$$"
  PFS_XML_FINAL="$PFS_FONT_ROOT/xml/$1"
  rm -rf "$PFS_XML_STAGE" || return 1
  mkdir "$PFS_XML_STAGE" || return 1
  PFS_BUILT_XML=0
  for PFS_XML_NAME in $PFS_XML_NAMES; do
    PFS_XML_ROM=$(pfs_rom_xml_path "$PFS_XML_NAME")
    [ -f "$PFS_XML_ROM" ] || continue
    pfs_patch_xml "$PFS_XML_ROM" "$PFS_XML_STAGE/$PFS_XML_NAME" "$1" \
      || { rm -rf "$PFS_XML_STAGE"; return 1; }
    PFS_BUILT_XML=$((PFS_BUILT_XML + 1))
  done
  [ "$PFS_BUILT_XML" -ge 1 ] || { rm -rf "$PFS_XML_STAGE"; return 1; }
  pfs_secure_font_path "$PFS_XML_STAGE" 0711 || { rm -rf "$PFS_XML_STAGE"; return 1; }
  rm -rf "$PFS_XML_FINAL" || { rm -rf "$PFS_XML_STAGE"; return 1; }
  mv "$PFS_XML_STAGE" "$PFS_XML_FINAL" || { rm -rf "$PFS_XML_STAGE"; return 1; }
}

# True when xml/<N>/ references generation N for all four targets in every
# file, and the referenced font copies exist.
pfs_xml_ready() {
  PFS_READY_COUNT=0
  [ -d "$PFS_FONT_ROOT/xml/$1" ] && [ ! -L "$PFS_FONT_ROOT/xml/$1" ] || return 1
  for PFS_READY_NAME in $PFS_XML_NAMES; do
    PFS_READY_XML="$PFS_FONT_ROOT/xml/$1/$PFS_READY_NAME"
    [ -e "$PFS_READY_XML" ] || continue
    [ -f "$PFS_READY_XML" ] && [ ! -L "$PFS_READY_XML" ] || return 1
    for PFS_READY_TARGET in $PFS_TARGET_NAMES; do
      grep -q "gen/$1/$PFS_READY_TARGET" "$PFS_READY_XML" || return 1
      [ -f "$PFS_FONT_ROOT/gen/$1/$PFS_READY_TARGET" ] || return 1
    done
    PFS_READY_COUNT=$((PFS_READY_COUNT + 1))
  done
  [ "$PFS_READY_COUNT" -ge 1 ]
}

# Ensures a published generation for the font resolved by pfs_resolve_font and
# sets PFS_GENERATION. The current generation is reused when it already holds
# this font; with "rebuild" (boot only, when nothing is bound) its XML is
# regenerated from the ROM so a ROM update is picked up. A changed font always
# gets a new generation, published only after its copies and XML verified.
pfs_prepare_redirect() {
  pfs_ensure_font_dirs || return 1
  PFS_CURRENT_GENERATION=$(pfs_current_generation 2>/dev/null) || PFS_CURRENT_GENERATION=0
  if [ "$PFS_CURRENT_GENERATION" -gt 0 ] && pfs_generation_matches "$PFS_CURRENT_GENERATION"; then
    PFS_GENERATION=$PFS_CURRENT_GENERATION
    pfs_relabel_generation "$PFS_GENERATION" || return 1
    if [ "${1:-}" = rebuild ] || ! pfs_xml_ready "$PFS_GENERATION"; then
      pfs_build_xml "$PFS_GENERATION" || return 1
    fi
    pfs_xml_ready "$PFS_GENERATION"
    return
  fi
  pfs_stage_new_generation || return 1
  if ! pfs_build_xml "$PFS_GENERATION" || ! pfs_xml_ready "$PFS_GENERATION"; then
    rm -rf "$PFS_FONT_ROOT/gen/$PFS_GENERATION" "$PFS_FONT_ROOT/xml/$PFS_GENERATION"
    return 1
  fi
  pfs_publish_generation "$PFS_GENERATION"
}

pfs_gc_generations() {
  for PFS_GC_PARENT in "$PFS_FONT_ROOT/gen" "$PFS_FONT_ROOT/xml"; do
    [ -d "$PFS_GC_PARENT" ] && [ ! -L "$PFS_GC_PARENT" ] || continue
    for PFS_GC_PATH in "$PFS_GC_PARENT"/* "$PFS_GC_PARENT"/.stage.*; do
      [ -e "$PFS_GC_PATH" ] || [ -L "$PFS_GC_PATH" ] || continue
      [ "${PFS_GC_PATH##*/}" = "$1" ] && continue
      rm -rf "$PFS_GC_PATH" || return 1
    done
  done
}

pfs_remove_font_root() {
  [ ! -L "$PFS_FONT_ROOT" ] || return 1
  case "$PFS_FONT_ROOT" in */persian_font_switcher) ;; *) return 1 ;; esac
  rm -rf "$PFS_FONT_ROOT"
}

pfs_pid_of() {
  "$PFS_PIDOF_BIN" "$1" 2>/dev/null | awk '{print $1}'
}

pfs_mnt_ns() {
  readlink "$PFS_PROC_ROOT/$1/ns/mnt" 2>/dev/null
}

# True only once system_server has unshared into its own mount namespace.
# Binding before that would land in zygote's (or init's) namespace and be
# inherited by apps. Fails closed whenever a namespace cannot be read.
pfs_ss_isolated() {
  [ -n "$1" ] || return 1
  PFS_SS_NS=$(pfs_mnt_ns "$1")
  PFS_INIT_NS=$(pfs_mnt_ns 1)
  [ -n "$PFS_SS_NS" ] && [ -n "$PFS_INIT_NS" ] && [ "$PFS_INIT_NS" != "$PFS_SS_NS" ] || return 1
  PFS_ZYGOTES_SEEN=0
  for PFS_ZYGOTE_NAME in zygote64 zygote; do
    PFS_ZYGOTE_PID=$(pfs_pid_of "$PFS_ZYGOTE_NAME")
    [ -n "$PFS_ZYGOTE_PID" ] || continue
    PFS_ZYGOTE_NS=$(pfs_mnt_ns "$PFS_ZYGOTE_PID")
    [ -n "$PFS_ZYGOTE_NS" ] && [ "$PFS_ZYGOTE_NS" != "$PFS_SS_NS" ] || return 1
    PFS_ZYGOTES_SEEN=$((PFS_ZYGOTES_SEEN + 1))
  done
  [ "$PFS_ZYGOTES_SEEN" -ge 1 ]
}

# Prints the generation of this module's bind when it is the topmost mount on
# /system/etc/<name> in the process's namespace. Other modules' mounts on the
# same path are recognized by their source root and never treated as ours.
pfs_bound_generation() {
  awk -v target="/system/etc/$2" -v name="$2" '
    $5 == target { root = $4 }
    END {
      suffix = "/persian_font_switcher/xml/"
      at = index(root, suffix)
      if (!at) exit 1
      rest = substr(root, at + length(suffix))
      split(rest, parts, "/")
      if (parts[1] !~ /^[0-9]+$/ || rest != parts[1] "/" name) exit 1
      print parts[1]
    }' "$PFS_PROC_ROOT/$1/mountinfo" 2>/dev/null
}

pfs_bind_present() {
  [ -n "$(pfs_bound_generation "$1" "$2")" ]
}

pfs_any_bind_present() {
  for PFS_PRESENT_NAME in $PFS_XML_NAMES; do
    pfs_bind_present "$1" "$PFS_PRESENT_NAME" && return 0
  done
  return 1
}

# Generation bound for the primary font XML, if any.
pfs_active_bind_generation() {
  for PFS_ACTIVE_NAME in $PFS_XML_NAMES; do
    PFS_ACTIVE_GEN=$(pfs_bound_generation "$1" "$PFS_ACTIVE_NAME")
    [ -n "$PFS_ACTIVE_GEN" ] && { printf '%s\n' "$PFS_ACTIVE_GEN"; return 0; }
  done
  return 1
}

pfs_unbind_name() {
  PFS_UNBIND_TRIES=0
  while pfs_bind_present "$1" "$2"; do
    PFS_UNBIND_TRIES=$((PFS_UNBIND_TRIES + 1))
    [ "$PFS_UNBIND_TRIES" -le 3 ] || return 1
    "$PFS_NSENTER_BIN" -t "$1" -m -- umount "/system/etc/$2" >/dev/null 2>&1 || return 1
  done
}

# Removes only this module's binds, and only while they are topmost.
pfs_unbind_all() {
  pfs_ss_isolated "$1" || return 1
  for PFS_UNBIND_NAME in $PFS_XML_NAMES; do
    pfs_unbind_name "$1" "$PFS_UNBIND_NAME" || return 1
  done
}

# Binds xml/<N>/ on top of /system/etc inside system_server's namespace,
# replacing an older bind of this module first.
pfs_bind_all() {
  pfs_ss_isolated "$1" || return 1
  pfs_xml_ready "$2" || return 1
  PFS_BIND_COUNT=0
  for PFS_BIND_NAME in $PFS_XML_NAMES; do
    PFS_BIND_SOURCE="$PFS_FONT_ROOT/xml/$2/$PFS_BIND_NAME"
    if [ ! -f "$PFS_BIND_SOURCE" ]; then
      pfs_unbind_name "$1" "$PFS_BIND_NAME" || return 1
      continue
    fi
    if [ "$(pfs_bound_generation "$1" "$PFS_BIND_NAME")" != "$2" ]; then
      pfs_unbind_name "$1" "$PFS_BIND_NAME" || return 1
      "$PFS_NSENTER_BIN" -t "$1" -m -- mount -o bind "$PFS_BIND_SOURCE" "/system/etc/$PFS_BIND_NAME" \
        >/dev/null 2>&1 || return 1
      [ "$(pfs_bound_generation "$1" "$PFS_BIND_NAME")" = "$2" ] || return 1
    fi
    PFS_BIND_COUNT=$((PFS_BIND_COUNT + 1))
  done
  [ "$PFS_BIND_COUNT" -ge 1 ]
}

# FontManagerService publishes its binder only after it has built the font map
# that apps receive.
pfs_font_service_published() {
  "$PFS_SERVICE_BIN" check font 2>/dev/null | grep -q ': found'
}

# The font service re-parses the XML for dump, which proves the patched config
# parses and that its four paths resolve to readable files.
pfs_dump_has_generation() {
  PFS_DUMP_COUNT=$("$PFS_DUMPSYS_BIN" font 2>/dev/null | grep -c "gen/$1/NotoNaskhArabic" || true)
  case "$PFS_DUMP_COUNT" in ''|*[!0-9]*) return 1 ;; esac
  [ "$PFS_DUMP_COUNT" -ge 4 ]
}

# Reads the font map a process actually received from the font service (its
# shared-memory mapping) and prints served, stock, or unknown. The map is
# mapped read-only and is the largest such region, so read-only regions are
# checked largest first; the much larger JIT caches are skipped (reading them
# took about 45 s on device). Ashmem regions are unnamed on some kernels.
pfs_served_map_state() {
  PFS_SERVED=unknown
  [ -n "$1" ] && [ -r "$PFS_PROC_ROOT/$1/maps" ] || { printf '%s\n' "$PFS_SERVED"; return 0; }
  PFS_SERVED_RANGES=$(awk '$2 == "r--s" && ($6 ~ /^\/dev\/ashmem/ || $6 ~ /^\/memfd:/) && $6 !~ /jit/ { print $1 }' \
    "$PFS_PROC_ROOT/$1/maps" 2>/dev/null \
    | while IFS=- read -r PFS_RANGE_START PFS_RANGE_END; do
        printf '%s %s-%s\n' "$((0x$PFS_RANGE_END - 0x$PFS_RANGE_START))" "$PFS_RANGE_START" "$PFS_RANGE_END"
      done | sort -rn | cut -d' ' -f2)
  for PFS_SERVED_RANGE in $PFS_SERVED_RANGES; do
    PFS_SERVED_FILE="$PFS_PROC_ROOT/$1/map_files/$PFS_SERVED_RANGE"
    [ -r "$PFS_SERVED_FILE" ] || continue
    grep -a -q 'NotoNaskhArabic' "$PFS_SERVED_FILE" 2>/dev/null || continue
    # A process holds one font map; the first region naming the fonts is it.
    if grep -a -q "gen/$2/NotoNaskhArabic" "$PFS_SERVED_FILE" 2>/dev/null; then
      PFS_SERVED=served
    else
      PFS_SERVED=stock
    fi
    break
  done
  printf '%s\n' "$PFS_SERVED"
}

# FontManagerService builds the boot font map off the main thread, after its
# binder is already published, then maps it into system_server itself. Waits
# for that copy and prints served or stock, or unknown if it does not appear
# in time or system_server exits. Only the boot map is mapped this way; a
# `cmd font restart` rebuild is synchronous instead.
pfs_wait_server_map() {
  PFS_MAP_DEADLINE=$(($(pfs_uptime_seconds) + ${3:-90}))
  PFS_MAP_TICKS=0
  while [ -d "$PFS_PROC_ROOT/$1" ]; do
    PFS_SERVER_MAP=$(pfs_served_map_state "$1" "$2")
    if [ "$PFS_SERVER_MAP" != unknown ]; then
      printf '%s\n' "$PFS_SERVER_MAP"
      return 0
    fi
    PFS_MAP_TICKS=$((PFS_MAP_TICKS + 1))
    [ "$(pfs_uptime_seconds)" -lt "$PFS_MAP_DEADLINE" ] \
      && [ "$PFS_MAP_TICKS" -lt "${PFS_MAP_MAX_TICKS:-1000}" ] || break
    sleep "${PFS_MAP_POLL:-0.2}"
  done
  printf '%s\n' unknown
}

pfs_restart_font_service() {
  "$PFS_CMD_BIN" font restart >/dev/null 2>&1
}

# Prints the default launcher: the HOME role holder. Until the first unlock
# after boot, HOME resolves to Settings' FallbackHome instead, which is never
# the launcher and must not be stopped.
pfs_home_package() {
  PFS_HOME_PACKAGE=$("$PFS_CMD_BIN" role get-role-holders android.app.role.HOME 2>/dev/null \
    | tr ';, ' '\n\n\n' | sed -n '1p')
  if [ -z "$PFS_HOME_PACKAGE" ]; then
    PFS_HOME_PACKAGE=$("$PFS_CMD_BIN" package resolve-activity --brief \
      -a android.intent.action.MAIN -c android.intent.category.HOME 2>/dev/null \
      | tail -n 1 | cut -d/ -f1)
  fi
  case "$PFS_HOME_PACKAGE" in
    ''|android|com.android.settings|*[!A-Za-z0-9._]*) return 1 ;;
  esac
  printf '%s\n' "$PFS_HOME_PACKAGE"
}

# Restarts the UI processes that started before a late font-map rebuild.
# SystemUI is persistent and respawns; the launcher relaunches as HOME.
pfs_restart_ui() {
  PFS_SYSUI_PID=$(pfs_pid_of com.android.systemui)
  if [ -n "$PFS_SYSUI_PID" ]; then
    "$PFS_KILL_BIN" "$PFS_SYSUI_PID" 2>/dev/null || true
  fi
  if PFS_HOME_PACKAGE=$(pfs_home_package); then
    "$PFS_AM_BIN" force-stop "$PFS_HOME_PACKAGE" >/dev/null 2>&1 || true
  fi
}

# Waits for a SystemUI process different from the given pid, then prints it.
pfs_wait_new_systemui() {
  PFS_NEW_UI_WAITED=0
  while [ "$PFS_NEW_UI_WAITED" -lt "${2:-30}" ]; do
    PFS_NEW_UI=$(pfs_pid_of com.android.systemui)
    if [ -n "$PFS_NEW_UI" ] && [ "$PFS_NEW_UI" != "$1" ]; then
      printf '%s\n' "$PFS_NEW_UI"
      return 0
    fi
    sleep 1
    PFS_NEW_UI_WAITED=$((PFS_NEW_UI_WAITED + 1))
  done
  return 1
}

pfs_guard_count() {
  PFS_GUARD_VALUE=0
  if [ -f "$PFS_GUARD_FILE" ] && [ ! -L "$PFS_GUARD_FILE" ]; then
    IFS= read -r PFS_GUARD_VALUE <"$PFS_GUARD_FILE" 2>/dev/null || PFS_GUARD_VALUE=0
  fi
  case "$PFS_GUARD_VALUE" in ''|*[!0-9]*) PFS_GUARD_VALUE=0 ;; esac
  printf '%s\n' "$PFS_GUARD_VALUE"
}

pfs_guard_tripped() {
  [ "$(pfs_guard_count)" -ge "$PFS_GUARD_LIMIT" ]
}

pfs_guard_set() {
  [ ! -L "$PFS_GUARD_FILE" ] || return 1
  printf '%s\n' "$1" >"$PFS_GUARD_FILE.tmp.$$" || return 1
  chmod 0600 "$PFS_GUARD_FILE.tmp.$$" || { rm -f "$PFS_GUARD_FILE.tmp.$$"; return 1; }
  mv -f "$PFS_GUARD_FILE.tmp.$$" "$PFS_GUARD_FILE" || { rm -f "$PFS_GUARD_FILE.tmp.$$"; return 1; }
  sync 2>/dev/null || true
}

# Counts boots that started the redirect but never reached boot completion.
pfs_guard_enter() {
  pfs_guard_set $(($(pfs_guard_count) + 1))
}

pfs_guard_trip() {
  pfs_guard_set "$PFS_GUARD_LIMIT"
}

pfs_guard_clear() {
  rm -f "$PFS_GUARD_FILE"
}

pfs_launch_watcher() {
  pfs_ensure_runtime_dir || return 1
  PFS_WATCHER_SCRIPT="$PFS_DIR/scripts/redirect-watcher.sh"
  # Close inherited lock descriptors so the resident watcher can never keep an
  # operation lock held. BusyBox's setsid runs a bare `sh` in-process in
  # standalone mode, where the watcher's flock then fails; an absolute path
  # makes it exec a fresh shell.
  if PFS_WATCHER_BUSYBOX=$(pfs_busybox); then
    ASH_STANDALONE=1 "$PFS_WATCHER_BUSYBOX" setsid "$PFS_WATCHER_BUSYBOX" sh "$PFS_WATCHER_SCRIPT" "$@" \
      </dev/null >>"$PFS_RUNTIME_DIR/watcher.log" 2>&1 6>&- 7>&- 8>&- 9>&- &
  elif command -v setsid >/dev/null 2>&1; then
    setsid sh "$PFS_WATCHER_SCRIPT" "$@" </dev/null >>"$PFS_RUNTIME_DIR/watcher.log" 2>&1 6>&- 7>&- 8>&- 9>&- &
  else
    nohup sh "$PFS_WATCHER_SCRIPT" "$@" </dev/null >>"$PFS_RUNTIME_DIR/watcher.log" 2>&1 6>&- 7>&- 8>&- 9>&- &
  fi
  PFS_WATCHER_PID=$!
  printf '%s\n' "$PFS_WATCHER_PID" >"$PFS_RUNTIME_DIR/watcher.pid" 2>/dev/null || true
  pfs_detach_cgroups "$PFS_WATCHER_PID"
}

# Android init kills every process in a finished boot service's cgroup, and
# setsid does not leave a cgroup. Moving the watcher to the root cgroups, as
# KernelSU and Magisk do for module scripts, keeps it alive. Best-effort.
pfs_detach_cgroups() {
  for PFS_CGROUP_ROOT in /acct /dev/cg2_bpf /sys/fs/cgroup /dev/memcg/apps; do
    [ -w "$PFS_CGROUP_ROOT/cgroup.procs" ] || continue
    printf '%s\n' "$1" >"$PFS_CGROUP_ROOT/cgroup.procs" 2>/dev/null || true
  done
}

pfs_watcher_running() {
  [ -f "$PFS_RUNTIME_DIR/watcher.lock" ] || return 1
  # toybox flock only accepts a file descriptor; the probe lock is released when
  # the subshell exits.
  if (exec 7>>"$PFS_RUNTIME_DIR/watcher.lock" && flock -n 7) 2>/dev/null; then
    return 1
  fi
  return 0
}

# Maps a staged generation back to the bundled or custom font it contains.
pfs_font_for_generation() {
  PFS_GEN_DIR="$PFS_FONT_ROOT/gen/$1"
  [ -d "$PFS_GEN_DIR" ] || return 1
  PFS_GEN_HASHES=$(sha256sum \
    "$PFS_GEN_DIR/NotoNaskhArabicUI-Regular.ttf" \
    "$PFS_GEN_DIR/NotoNaskhArabic-Regular.ttf" \
    "$PFS_GEN_DIR/NotoNaskhArabicUI-Bold.ttf" \
    "$PFS_GEN_DIR/NotoNaskhArabic-Bold.ttf" 2>/dev/null) || return 1
  PFS_GEN_REGULAR=$(printf '%s\n' "$PFS_GEN_HASHES" | sed -n '1s/[[:space:]].*//p')
  PFS_GEN_REGULAR_ELEGANT=$(printf '%s\n' "$PFS_GEN_HASHES" | sed -n '2s/[[:space:]].*//p')
  PFS_GEN_BOLD=$(printf '%s\n' "$PFS_GEN_HASHES" | sed -n '3s/[[:space:]].*//p')
  PFS_GEN_BOLD_ELEGANT=$(printf '%s\n' "$PFS_GEN_HASHES" | sed -n '4s/[[:space:]].*//p')
  [ -n "$PFS_GEN_REGULAR" ] && [ "$PFS_GEN_REGULAR" = "$PFS_GEN_REGULAR_ELEGANT" ] \
    && [ -n "$PFS_GEN_BOLD" ] && [ "$PFS_GEN_BOLD" = "$PFS_GEN_BOLD_ELEGANT" ] || return 1
  for PFS_GEN_CANDIDATE in $(sed -n 's/.*"id": "\([a-z0-9_-]*\)".*/\1/p' "$PFS_MANIFEST"); do
    [ "$PFS_GEN_CANDIDATE" = system-default ] && continue
    if pfs_resolve_font "$PFS_GEN_CANDIDATE" \
      && [ "$PFS_GEN_REGULAR" = "$PFS_REGULAR_HASH" ] && [ "$PFS_GEN_BOLD" = "$PFS_BOLD_HASH" ]; then
      printf '%s\n' "$PFS_GEN_CANDIDATE"
      return 0
    fi
  done
  if [ -d "$PFS_CUSTOM_DIR" ]; then
    for PFS_GEN_CUSTOM in "$PFS_CUSTOM_DIR"/custom-*; do
      [ -d "$PFS_GEN_CUSTOM" ] || continue
      PFS_GEN_CANDIDATE=${PFS_GEN_CUSTOM##*/}
      if pfs_resolve_font "$PFS_GEN_CANDIDATE" \
        && [ "$PFS_GEN_REGULAR" = "$PFS_REGULAR_HASH" ] && [ "$PFS_GEN_BOLD" = "$PFS_BOLD_HASH" ]; then
        printf '%s\n' "$PFS_GEN_CANDIDATE"
        return 0
      fi
    done
  fi
  return 1
}

# Resolves a selection and verifies its source files against recorded hashes.
pfs_resolve_verified() {
  pfs_resolve_font "$1" || return 1
  [ -f "$PFS_REGULAR_SOURCE" ] && [ -f "$PFS_BOLD_SOURCE" ] || return 2
  [ "$(sha256sum "$PFS_REGULAR_SOURCE" | awk '{print $1}')" = "$PFS_REGULAR_HASH" ] \
    && [ "$(sha256sum "$PFS_BOLD_SOURCE" | awk '{print $1}')" = "$PFS_BOLD_HASH" ] || return 3
}
