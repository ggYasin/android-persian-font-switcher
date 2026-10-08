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

# "Active" is what FontManagerService served to apps this boot. It is derived
# from the redirect record of the current system_server and, while
# verification is pending, the font map SystemUI received. The bind itself is
# released once the map is built, so it is not evidence either way. It is
# never derived from the saved selection.
ACTIVE=unknown
ACTIVE_SCOPE=unavailable
REDIRECT=$(pfs_state_get state 2>/dev/null) || REDIRECT=""
[ -n "$REDIRECT" ] || REDIRECT=none
STATE_PID=$(pfs_state_get ss_pid 2>/dev/null) || STATE_PID=""
STATE_GENERATION=$(pfs_state_get generation 2>/dev/null) || STATE_GENERATION=""
SS=$(pfs_pid_of system_server)

if [ -n "$SS" ] && [ -r "$PFS_PROC_ROOT/$SS/mountinfo" ]; then
  BOUND_GENERATION=$(pfs_active_bind_generation "$SS" 2>/dev/null) || BOUND_GENERATION=""
  CURRENT_SERVER=false
  [ "$STATE_PID" = "$SS" ] && CURRENT_SERVER=true
  case "$REDIRECT" in
    verified)
      if [ "$CURRENT_SERVER" = true ] && [ -n "$STATE_GENERATION" ]; then
        ACTIVE=$(pfs_font_for_generation "$STATE_GENERATION" 2>/dev/null) || ACTIVE=unknown
      elif [ "$CURRENT_SERVER" = false ] && [ -z "$BOUND_GENERATION" ]; then
        # A restarted system_server without this module's bind serves stock.
        ACTIVE=system-default
      fi
      ;;
    bound)
      if [ "$CURRENT_SERVER" = true ] && [ -n "$STATE_GENERATION" ]; then
        case "$(pfs_served_map_state "$(pfs_pid_of com.android.systemui)" "$STATE_GENERATION")" in
          served) ACTIVE=$(pfs_font_for_generation "$STATE_GENERATION" 2>/dev/null) || ACTIVE=unknown ;;
          stock) ACTIVE=system-default ;;
        esac
      fi
      ;;
    inactive|guard-tripped|failed)
      [ -n "$BOUND_GENERATION" ] || ACTIVE=system-default
      ;;
  esac
  [ "$ACTIVE" = unknown ] || ACTIVE_SCOPE=font-service
fi

if [ "$ACTIVE" = unknown ]; then
  case "$REDIRECT" in
    waiting|bound) RESTART_REQUIRED=unknown ;;
    *) if [ "$SELECTED" = system-default ]; then RESTART_REQUIRED=unknown; else RESTART_REQUIRED=true; fi ;;
  esac
elif [ "$ACTIVE" = "$SELECTED" ]; then
  RESTART_REQUIRED=false
else
  RESTART_REQUIRED=true
fi

if pfs_guard_tripped; then
  BOOT_GUARD=tripped
else
  BOOT_GUARD=ok
fi
GENERATION=$(pfs_current_generation 2>/dev/null) || GENERATION=none

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
  "redirect=$REDIRECT" \
  "generation=$GENERATION" \
  "boot_guard=$BOOT_GUARD" \
  "fontloader=$FONTLOADER" \
  "layout=$LAYOUT" \
  "targets=$TARGETS"
