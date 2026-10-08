#!/system/bin/sh
# Activates the saved selection without a reboot: binds the selection's XML
# generation inside system_server's namespace just long enough for the font
# service to rebuild its font map from it, then restarts SystemUI and the
# launcher. Other apps pick up the change when they next start.
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$SCRIPT_DIR/lib.sh"

fail() {
  printf '%s\n' "status=error" "code=$1" "message=$2"
  exit "$3"
}

[ "$#" -eq 0 ] || fail invalid-arguments "No arguments are accepted." 2
pfs_validate_targets || fail invalid-target-layout "Supported target state is missing or invalid; reinstall the module." 3

LOCK_FILE="$PFS_DIR/.apply-lock"
if ! pfs_acquire_lock "$LOCK_FILE"; then
  if [ "${PFS_LOCK_ERROR:-unavailable}" = "busy" ]; then
    fail busy "Another font operation is already in progress." 4
  fi
  fail lock-unavailable "The operation lock is unavailable." 7
fi
trap 'pfs_release_lock "$LOCK_FILE"' 0
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

SS=$(pfs_pid_of system_server)
pfs_ss_isolated "$SS" || fail system-server-unavailable "system_server's private mount namespace could not be identified." 9
SELECTION=$(pfs_read_selection)

if [ "$SELECTION" = system-default ]; then
  if ! pfs_unbind_all "$SS"; then
    pfs_write_state state=failed reason=live-unbind-failed "ss_pid=$SS"
    fail unbind-failed "The redirect could not be removed from system_server." 10
  fi
  pfs_restart_font_service || fail font-service-restart-failed "The font service did not rebuild its font map." 11
  pfs_restart_ui
  pfs_write_state state=inactive reason=system-default-live "ss_pid=$SS"
  pfs_log "live apply: System Default restored"
  printf '%s\n' "status=ok" "active=system-default" "message=Stock fonts restored. SystemUI and the launcher were restarted; other apps update when reopened."
  exit 0
fi

if pfs_resolve_verified "$SELECTION"; then
  :
else
  fail font-checksum-mismatch "The selected font failed integrity validation." 5
fi
pfs_prepare_redirect || fail redirect-prepare-failed "The font copies or patched font configuration could not be prepared." 8
GENERATION=$PFS_GENERATION

restore_stock() {
  pfs_unbind_all "$SS" || true
  pfs_restart_font_service || true
  pfs_write_state state=failed "reason=$1" "ss_pid=$SS" "generation=$GENERATION"
  pfs_log "live apply failed ($1); stock fonts restored"
}

if ! pfs_bind_all "$SS" "$GENERATION"; then
  restore_stock live-bind-failed
  fail bind-failed "The patched font configuration could not be bound into system_server; stock fonts were restored." 10
fi
if ! pfs_restart_font_service || ! pfs_dump_has_generation "$GENERATION"; then
  restore_stock live-config-mismatch
  pfs_restart_ui
  fail font-config-mismatch "The font service did not accept the patched configuration; stock fonts were restored." 11
fi
# The rebuilt map is held in memory; apps that NeoZygisk does not hide copy
# system_server's live mounts, so the bind must not outlive the rebuild.
pfs_unbind_all "$SS" || pfs_log "could not release the bind in system_server $SS"
OLD_UI=$(pfs_pid_of com.android.systemui)
pfs_restart_ui
NEW_UI=$(pfs_wait_new_systemui "$OLD_UI" "${PFS_UI_WAIT:-20}") || NEW_UI=""
SERVED=$(pfs_served_map_state "$NEW_UI" "$GENERATION")
if [ "$SERVED" = stock ]; then
  restore_stock live-not-served
  pfs_restart_ui
  fail font-not-served "The rebuilt font map did not reach SystemUI; stock fonts were restored." 12
fi
pfs_write_state state=verified mode=live "ss_pid=$SS" "generation=$GENERATION" "font=$SELECTION" \
  "served_check=$SERVED"
pfs_guard_clear
if ! pfs_watcher_running; then
  pfs_launch_watcher "$SS"
fi
pfs_log "live apply: gen $GENERATION ($SELECTION) active, served check $SERVED"
printf '%s\n' "status=ok" "active=$SELECTION" "generation=$GENERATION" \
  "message=Font applied. SystemUI and the launcher were restarted; other apps update when reopened."
