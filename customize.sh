#!/system/bin/sh

LEGACY_MODULE_ID="vazirmatn_persian_fallback"
THIRD_PARTY_MODULE_ID="Vazirmatn-Regular"
PFS_SYSTEM_ROOT="${PFS_TEST_SYSTEM_ROOT:-/system}"
PFS_ADB_ROOT="${PFS_TEST_ADB_ROOT:-/data/adb}"
FONT_CONFIG="$PFS_SYSTEM_ROOT/etc/fonts.xml"
DEVICE_API="${API:-$(getprop ro.build.version.sdk 2>/dev/null)}"

for REQUIRED_APPLET in awk base64 flock od sha256sum sync; do
  command -v "$REQUIRED_APPLET" >/dev/null 2>&1 \
    || abort "Required Android command is unavailable: $REQUIRED_APPLET"
done

check_conflict_dir() {
  CONFLICT_DIR="$1"
  [ -d "$CONFLICT_DIR" ] || return 0
  CONFLICT_ID=${CONFLICT_DIR##*/}
  [ "$CONFLICT_ID" = "persian_font_switcher" ] && return 0
  [ -e "$CONFLICT_DIR/disable" ] && return 0
  [ -e "$CONFLICT_DIR/remove" ] && return 0
  [ -e "$CONFLICT_DIR/skip_mount" ] && return 0

  if [ "$CONFLICT_ID" = "$LEGACY_MODULE_ID" ] || [ "$CONFLICT_ID" = "$THIRD_PARTY_MODULE_ID" ]; then
    abort "Conflicting font module '$CONFLICT_ID' is enabled. Disable/remove it, reboot, then install Persian Font Switcher."
  fi

  for TARGET_NAME in \
    NotoNaskhArabicUI-Regular.ttf \
    NotoNaskhArabicUI-Bold.ttf \
    NotoNaskhArabic-Regular.ttf \
    NotoNaskhArabic-Bold.ttf
  do
    if [ -e "$CONFLICT_DIR/system/fonts/$TARGET_NAME" ]; then
      abort "Enabled module '$CONFLICT_ID' also overlays $TARGET_NAME. Disable/remove it and reboot first."
    fi
  done

  if [ -e "$CONFLICT_DIR/system/.replace" ] || [ -e "$CONFLICT_DIR/system/fonts/.replace" ]; then
    abort "Enabled module '$CONFLICT_ID' replaces a parent of the Android font targets. Disable/remove it and reboot first."
  fi
}

for CONFLICT_ROOT in "$PFS_ADB_ROOT/modules" "$PFS_ADB_ROOT/modules_update"; do
  for CONFLICT_DIR in "$CONFLICT_ROOT"/*; do
    check_conflict_dir "$CONFLICT_DIR"
  done
done

case "$DEVICE_API" in
  31|32|33|34|35|36) ;;
  *) abort "Unsupported Android API: ${DEVICE_API:-unknown}. This release supports verified AOSP-style Android 12-16 layouts only." ;;
esac

if [ ! -f "$FONT_CONFIG" ]; then
  abort "Base Android font configuration is absent: $FONT_CONFIG"
fi

font_config_has_family() {
  PFS_WANTED_VARIANT=$1
  PFS_WANTED_REGULAR=$2
  PFS_WANTED_BOLD=$3
  awk -v wanted_variant="$PFS_WANTED_VARIANT" \
    -v wanted_regular="$PFS_WANTED_REGULAR" \
    -v wanted_bold="$PFS_WANTED_BOLD" -v sq="'" '
    function attr(text, key, value, pattern) {
      pattern = "(^|[[:space:]])" key "[[:space:]]*=[[:space:]]*(\"|" sq ")" value "(\"|" sq ")"
      return text ~ pattern
    }
    function has_attr(text, key) {
      return text ~ ("(^|[[:space:]])" key "[[:space:]]*=")
    }
    function trim(text) {
      sub(/^[[:space:]]+/, "", text)
      sub(/[[:space:]]+$/, "", text)
      return text
    }
    function font_entry(block, filename, weight, entries, count, index_, entry, start_, opening, body) {
      count = split(block, entries, "</font>")
      for (index_ = 1; index_ <= count; index_++) {
        entry = entries[index_]
        start_ = match(entry, /<font[[:space:]>]/)
        if (!start_) continue
        entry = substr(entry, start_)
        opening = substr(entry, 1, index(entry, ">"))
        body = substr(entry, length(opening) + 1)
        sub(/<.*/, "", body)
        if (trim(body) == filename && attr(opening, "weight", weight) \
          && (!has_attr(opening, "style") || attr(opening, "style", "normal"))) return 1
      }
      return 0
    }
    function family_matches(block, opening) {
      opening = substr(block, 1, index(block, ">"))
      return attr(opening, "lang", "und-Arab") \
        && attr(opening, "variant", wanted_variant) \
        && !has_attr(opening, "name") \
        && font_entry(block, wanted_regular, "400") \
        && font_entry(block, wanted_bold, "700")
    }
    {
      xml = xml " " $0
    }
    END {
      while (match(xml, /<!--/)) {
        before = substr(xml, 1, RSTART - 1)
        tail = substr(xml, RSTART + 4)
        close_comment = index(tail, "-->")
        if (!close_comment) { xml = before; break }
        xml = before substr(tail, close_comment + 3)
      }
      rest = xml
      while (match(rest, /<family[[:space:]>]/)) {
        rest = substr(rest, RSTART)
        close_family = index(rest, "</family>")
        if (!close_family) exit 1
        block = substr(rest, 1, close_family + 8)
        if (family_matches(block)) exit 0
        rest = substr(rest, close_family + 9)
      }
      exit 1
    }
  ' "$FONT_CONFIG"
}

if ! font_config_has_family compact NotoNaskhArabicUI-Regular.ttf NotoNaskhArabicUI-Bold.ttf; then
  abort "Unsupported ROM font configuration: the exact und-Arab compact Regular 400/Bold 700 fallback family is absent."
fi
if ! font_config_has_family elegant NotoNaskhArabic-Regular.ttf NotoNaskhArabic-Bold.ttf; then
  abort "Unsupported ROM font configuration: the exact und-Arab elegant Regular 400/Bold 700 fallback family is absent."
fi

mkdir -p "$MODPATH/state"
TARGETS_FILE="$MODPATH/state/supported-targets"
TARGETS_TMP="$MODPATH/state/.supported-targets.$$"
: >"$TARGETS_TMP"
for FONT_NAME in \
  NotoNaskhArabicUI-Regular.ttf \
  NotoNaskhArabicUI-Bold.ttf \
  NotoNaskhArabic-Regular.ttf \
  NotoNaskhArabic-Bold.ttf
do
  if [ ! -f "$PFS_SYSTEM_ROOT/fonts/$FONT_NAME" ]; then
    rm -f "$TARGETS_TMP"
    abort "Unsupported ROM font layout: expected system font file is absent: $FONT_NAME"
  fi
  printf '%s\n' "$FONT_NAME" >>"$TARGETS_TMP"
done
chmod 0600 "$TARGETS_TMP"
mv -f "$TARGETS_TMP" "$TARGETS_FILE"

ui_print "Detected complete AOSP compact/elegant Arabic fallback layout."

DESIRED_FONT="vazirmatn"
KSU_CONFIG="$PFS_ADB_ROOT/ksu/bin/ksud"
PFS_DATA_DIR="$PFS_ADB_ROOT/persian_font_switcher"
PFS_MODULE_DIR="$MODPATH"
export PFS_ADB_ROOT PFS_DATA_DIR PFS_MODULE_DIR
. "$MODPATH/scripts/lib.sh"
if [ -x "$KSU_CONFIG" ]; then
  SAVED_FONT=$(KSU_MODULE=persian_font_switcher "$KSU_CONFIG" module config get selected_font 2>/dev/null || true)
  if pfs_valid_selection "$SAVED_FONT"; then
    DESIRED_FONT="$SAVED_FONT"
  fi
fi

# KernelSU Next may extract ordinary payload scripts as 0644 regardless of the
# ZIP's Unix mode. Normalize runtime modes now, but invoke the initial apply via
# an explicit shell so installation never depends on extraction preserving +x.
set_perm "$MODPATH/customize.sh" 0 0 0755
set_perm_recursive "$MODPATH/scripts" 0 0 0755 0755

# Recreate WebUI preview copies from the module-owned persistent custom-font
# store. This is optional, best-effort update recovery: malformed/unreadable
# data, a stale lock, or a transient copy error must not block a valid install.
SYNC_LOG="$MODPATH/state/install-preview-sync.log"
if PFS_MODULE_DIR="$MODPATH" PFS_DATA_DIR="$PFS_DATA_DIR" sh "$MODPATH/scripts/sync-custom.sh" >"$SYNC_LOG" 2>&1; then
  SYNC_STATUS=0
else
  SYNC_STATUS=$?
fi
ui_print "Custom-font preview restore output (exit $SYNC_STATUS):"
while IFS= read -r SYNC_LINE || [ -n "$SYNC_LINE" ]; do
  ui_print "  $SYNC_LINE"
done <"$SYNC_LOG"
rm -f "$SYNC_LOG"
if [ "$SYNC_STATUS" -ne 0 ]; then
  ui_print "Warning: preview restoration failed unexpectedly; persistent custom data was left untouched and installation will continue."
fi

APPLY_LOG="$MODPATH/state/install-apply.log"
if PFS_MODULE_DIR="$MODPATH" PFS_DATA_DIR="$PFS_DATA_DIR" PFS_SKIP_KSU_CONFIG=1 sh "$MODPATH/scripts/apply-font.sh" "$DESIRED_FONT" >"$APPLY_LOG" 2>&1; then
  APPLY_STATUS=0
else
  APPLY_STATUS=$?
fi

ui_print "Initial font apply output (exit $APPLY_STATUS):"
while IFS= read -r APPLY_LINE || [ -n "$APPLY_LINE" ]; do
  ui_print "  $APPLY_LINE"
done <"$APPLY_LOG"
rm -f "$APPLY_LOG"

if [ "$APPLY_STATUS" -ne 0 ]; then
  abort "Failed to prepare the initial '$DESIRED_FONT' fallback overlay (exit $APPLY_STATUS). See the apply output above."
fi

# Reassert final installed modes after initialization. WebUI calls these
# scripts directly at runtime, so they must be executable in the installed tree.
set_perm "$MODPATH/customize.sh" 0 0 0755
set_perm_recursive "$MODPATH/scripts" 0 0 0755 0755
set_perm_recursive "$MODPATH/assets" 0 0 0755 0644
set_perm_recursive "$MODPATH/webroot" 0 0 0755 0644
set_perm_recursive "$MODPATH/state" 0 0 0700 0600
if [ -d "$MODPATH/system/fonts" ]; then
  set_perm_recursive "$MODPATH/system/fonts" 0 0 0755 0644
fi

ui_print "Persian Font Switcher prepared for API $DEVICE_API."
ui_print "Selected font: $DESIRED_FONT"
ui_print "A compatible systemless mount provider is required; reboot to activate."
