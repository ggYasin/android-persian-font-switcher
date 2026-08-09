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
  if [ -e "$PFS_DIR/skip_mount" ]; then
    printf '%s\n' system-default
    return 0
  fi

  # The module file is updated atomically with the overlay and is authoritative
  # at runtime. KernelSU config is a cross-update fallback only; it may be stale
  # if a best-effort config write failed after the module state commit.
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

pfs_enable_skip_mount() {
  PFS_SKIP_TMP="$PFS_DIR/.skip_mount.tmp.$$"
  : >"$PFS_SKIP_TMP" || return 1
  chmod 0600 "$PFS_SKIP_TMP" || { rm -f "$PFS_SKIP_TMP"; return 1; }
  mv -f "$PFS_SKIP_TMP" "$PFS_DIR/skip_mount" || { rm -f "$PFS_SKIP_TMP"; return 1; }
  return 0
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
