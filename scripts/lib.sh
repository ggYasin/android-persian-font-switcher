#!/system/bin/sh

PFS_MODULE_ID="persian_font_switcher"
PFS_SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PFS_DIR=${PFS_MODULE_DIR:-$(CDPATH= cd -- "$PFS_SCRIPT_DIR/.." && pwd)}
PFS_MANIFEST="$PFS_DIR/webroot/font-manifest.json"
PFS_STATE_DIR="$PFS_DIR/state"
PFS_STATE_FILE="$PFS_STATE_DIR/selected-font"
PFS_TARGETS_FILE="$PFS_STATE_DIR/supported-targets"
PFS_KSUD="/data/adb/ksu/bin/ksud"

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

pfs_json_field() {
  PFS_RECORD="$1"
  PFS_FIELD="$2"
  printf '%s\n' "$PFS_RECORD" | sed -n "s/.*\"$PFS_FIELD\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p"
}

pfs_valid_selection() {
  PFS_SELECTION="$1"
  pfs_valid_id "$PFS_SELECTION" || return 1
  [ "$PFS_SELECTION" = "system-default" ] && return 0
  [ -n "$(pfs_manifest_record "$PFS_SELECTION")" ]
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

  if [ -x "$PFS_KSUD" ]; then
    PFS_CONFIG_SELECTION=$(KSU_MODULE="$PFS_MODULE_ID" "$PFS_KSUD" module config get selected_font 2>/dev/null || true)
    if pfs_valid_selection "$PFS_CONFIG_SELECTION"; then
      printf '%s\n' "$PFS_CONFIG_SELECTION"
      return 0
    fi
  fi

  if [ -f "$PFS_STATE_FILE" ]; then
    IFS= read -r PFS_FILE_SELECTION <"$PFS_STATE_FILE" || true
    if pfs_valid_selection "$PFS_FILE_SELECTION"; then
      printf '%s\n' "$PFS_FILE_SELECTION"
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

pfs_mark_reboot_required() {
  if [ "${PFS_SKIP_KSU_CONFIG:-0}" != "1" ] && [ -x "$PFS_KSUD" ]; then
    KSU_MODULE="$PFS_MODULE_ID" "$PFS_KSUD" module config set --temp reboot_required true >/dev/null 2>&1 || true
  fi
}

pfs_reboot_required() {
  if [ -x "$PFS_KSUD" ]; then
    PFS_REBOOT_VALUE=$(KSU_MODULE="$PFS_MODULE_ID" "$PFS_KSUD" module config get reboot_required 2>/dev/null || true)
    [ "$PFS_REBOOT_VALUE" = "true" ] || [ "$PFS_REBOOT_VALUE" = "1" ]
    return
  fi
  return 1
}
