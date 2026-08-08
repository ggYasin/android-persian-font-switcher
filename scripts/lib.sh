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
    *[!a-z0-9_-]*|-*|_*|*--*|*__*) return 1 ;;
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
  case "$PFS_CUSTOM_ID" in custom-[0-9a-f]*) ;; *) return 1 ;; esac
  printf '%s\n' "$PFS_CUSTOM_DIR/$PFS_CUSTOM_ID"
}

pfs_read_hash_file() {
  PFS_HASH_FILE="$1"
  [ -f "$PFS_HASH_FILE" ] || return 1
  IFS= read -r PFS_STORED_HASH <"$PFS_HASH_FILE" || return 1
  [ "${#PFS_STORED_HASH}" -eq 64 ] || return 1
  case "$PFS_STORED_HASH" in *[!0-9a-f]*) return 1 ;; esac
  printf '%s\n' "$PFS_STORED_HASH"
}

pfs_custom_valid() {
  PFS_CUSTOM_CHECK_ID="$1"
  PFS_CUSTOM_CHECK_DIR=$(pfs_custom_dir "$PFS_CUSTOM_CHECK_ID") || return 1
  [ -f "$PFS_CUSTOM_CHECK_DIR/regular.ttf" ] \
    && [ -f "$PFS_CUSTOM_CHECK_DIR/bold.ttf" ] \
    && [ -s "$PFS_CUSTOM_CHECK_DIR/name.b64" ] || return 1
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
  : >"$PFS_SKIP_TMP"
  chmod 0600 "$PFS_SKIP_TMP"
  mv -f "$PFS_SKIP_TMP" "$PFS_DIR/skip_mount"
}

pfs_write_selection() {
  PFS_NEW_SELECTION="$1"
  mkdir -p "$PFS_STATE_DIR"
  PFS_STATE_TMP="$PFS_STATE_FILE.tmp.$$"
  printf '%s\n' "$PFS_NEW_SELECTION" >"$PFS_STATE_TMP"
  chmod 0600 "$PFS_STATE_TMP"
  mv -f "$PFS_STATE_TMP" "$PFS_STATE_FILE"
  PFS_CONFIG_BACKEND="module-file"

  if [ "${PFS_SKIP_KSU_CONFIG:-0}" != "1" ] && [ -x "$PFS_KSUD" ]; then
    if KSU_MODULE="$PFS_MODULE_ID" "$PFS_KSUD" module config set selected_font "$PFS_NEW_SELECTION" >/dev/null 2>&1; then
      PFS_CONFIG_BACKEND="kernelsu-config"
    fi
  fi
}
