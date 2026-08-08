#!/system/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$SCRIPT_DIR/lib.sh"

SELECTED=$(pfs_read_selection)

if pfs_validate_targets; then
  TARGETS=$(tr '\n' ',' <"$PFS_TARGETS_FILE" | sed 's/,$//')
  LAYOUT=valid
else
  TARGETS=""
  LAYOUT=invalid
fi

HASH_OUTPUT=""
PFS_NSENTER_BIN=${PFS_NSENTER_BIN:-nsenter}
if [ -n "${PFS_EFFECTIVE_FONT_DIR:-}" ]; then
  if HASH_OUTPUT=$(sha256sum \
    "$PFS_EFFECTIVE_FONT_DIR/NotoNaskhArabicUI-Regular.ttf" \
    "$PFS_EFFECTIVE_FONT_DIR/NotoNaskhArabic-Regular.ttf" \
    "$PFS_EFFECTIVE_FONT_DIR/NotoNaskhArabicUI-Bold.ttf" \
    "$PFS_EFFECTIVE_FONT_DIR/NotoNaskhArabic-Bold.ttf" 2>/dev/null); then
    ACTIVE_SCOPE=test-root
  else
    ACTIVE_SCOPE=unavailable
    HASH_OUTPUT=""
  fi
elif command -v "$PFS_NSENTER_BIN" >/dev/null 2>&1 && [ -r /proc/1/ns/mnt ]; then
  if HASH_OUTPUT=$("$PFS_NSENTER_BIN" -t 1 -m -- sha256sum \
    /system/fonts/NotoNaskhArabicUI-Regular.ttf \
    /system/fonts/NotoNaskhArabic-Regular.ttf \
    /system/fonts/NotoNaskhArabicUI-Bold.ttf \
    /system/fonts/NotoNaskhArabic-Bold.ttf 2>/dev/null); then
    ACTIVE_SCOPE=pid1-mount
  else
    ACTIVE_SCOPE=unavailable
    HASH_OUTPUT=""
  fi
else
  ACTIVE_SCOPE=unavailable
fi

ACTIVE=unknown
ACTIVE_REGULAR=$(printf '%s\n' "$HASH_OUTPUT" | sed -n '1s/[[:space:]].*//p')
ACTIVE_REGULAR_ELEGANT=$(printf '%s\n' "$HASH_OUTPUT" | sed -n '2s/[[:space:]].*//p')
ACTIVE_BOLD=$(printf '%s\n' "$HASH_OUTPUT" | sed -n '3s/[[:space:]].*//p')
ACTIVE_BOLD_ELEGANT=$(printf '%s\n' "$HASH_OUTPUT" | sed -n '4s/[[:space:]].*//p')

if [ -n "$ACTIVE_REGULAR" ] \
  && [ "$ACTIVE_REGULAR" = "$ACTIVE_REGULAR_ELEGANT" ] \
  && [ -n "$ACTIVE_BOLD" ] \
  && [ "$ACTIVE_BOLD" = "$ACTIVE_BOLD_ELEGANT" ]; then
  for FONT_ID in $(sed -n 's/.*"id": "\([a-z0-9_-]*\)".*/\1/p' "$PFS_MANIFEST"); do
    [ "$FONT_ID" = system-default ] && continue
    if pfs_resolve_font "$FONT_ID" \
      && [ "$ACTIVE_REGULAR" = "$PFS_REGULAR_HASH" ] \
      && [ "$ACTIVE_BOLD" = "$PFS_BOLD_HASH" ]; then
      ACTIVE="$FONT_ID"
      break
    fi
  done
  if [ "$ACTIVE" = unknown ] && [ -d "$PFS_CUSTOM_DIR" ]; then
    for CUSTOM_PATH in "$PFS_CUSTOM_DIR"/custom-*; do
      [ -d "$CUSTOM_PATH" ] || continue
      FONT_ID=${CUSTOM_PATH##*/}
      if pfs_resolve_font "$FONT_ID" \
        && [ "$ACTIVE_REGULAR" = "$PFS_REGULAR_HASH" ] \
        && [ "$ACTIVE_BOLD" = "$PFS_BOLD_HASH" ]; then
        ACTIVE="$FONT_ID"
        break
      fi
    done
  fi
fi

if [ "$ACTIVE" = unknown ] && [ "$SELECTED" = system-default ]; then
  RESTART_REQUIRED=unknown
elif [ "$ACTIVE" = "$SELECTED" ]; then
  RESTART_REQUIRED=false
else
  RESTART_REQUIRED=true
fi

FONTLOADER_DIR="$PFS_ADB_ROOT/modules/fontloader"
FONTLOADER_UPDATE_DIR="$PFS_ADB_ROOT/modules_update/fontloader"
FONTLOADER_INSTALLED=false
FONTLOADER_STAGED=false
if [ -f "$FONTLOADER_DIR/module.prop" ] && grep -q '^id=fontloader$' "$FONTLOADER_DIR/module.prop"; then
  FONTLOADER_INSTALLED=true
fi
if [ -f "$FONTLOADER_UPDATE_DIR/module.prop" ] && grep -q '^id=fontloader$' "$FONTLOADER_UPDATE_DIR/module.prop"; then
  FONTLOADER_STAGED=true
fi

if [ "$FONTLOADER_STAGED" = true ]; then
  if [ "$FONTLOADER_INSTALLED" = true ]; then
    FONTLOADER=pending-install-or-update
  else
    FONTLOADER=pending-install
  fi
elif [ "$FONTLOADER_INSTALLED" = true ]; then
  if [ -e "$FONTLOADER_DIR/remove" ]; then
    FONTLOADER=pending-removal
  elif [ -e "$FONTLOADER_DIR/disable" ]; then
    FONTLOADER=disabled
  else
    FONTLOADER=enabled
  fi
else
  FONTLOADER=not-detected
fi

printf '%s\n' \
  "status=ok" \
  "active=$ACTIVE" \
  "selected=$SELECTED" \
  "restart_required=$RESTART_REQUIRED" \
  "active_scope=$ACTIVE_SCOPE" \
  "fontloader=$FONTLOADER" \
  "layout=$LAYOUT" \
  "targets=$TARGETS"
