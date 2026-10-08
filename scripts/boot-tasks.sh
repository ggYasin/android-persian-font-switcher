#!/system/bin/sh
# Boot-stage orchestration for the mount-free font redirect.
#
#   post-fs-data    stage the selected font and patched XML, apply the boot
#                   guard, and start the system_server watcher before zygote
#   service         relaunch the watcher if it is missing and schedule the
#                   boot-completed verification as a fallback
#   boot-completed  verify the redirect reached the font map apps received,
#                   repair a late bind, roll back a bad one, make sure no bind
#                   is left in system_server, clear the guard

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$SCRIPT_DIR/lib.sh"

MODE=${1:-}
LOCK_FILE="$PFS_DIR/.apply-lock"

stage_post_fs_data() {
  pfs_ensure_runtime_dir || exit 0
  rm -f "$PFS_REDIRECT_STATE" "$PFS_RUNTIME_DIR/boot-completed.done"
  for PFS_ROTATE in events watcher; do
    if [ -f "$PFS_RUNTIME_DIR/$PFS_ROTATE.log" ]; then
      mv -f "$PFS_RUNTIME_DIR/$PFS_ROTATE.log" "$PFS_RUNTIME_DIR/$PFS_ROTATE.previous.log" 2>/dev/null || true
    fi
  done

  SELECTION=$(pfs_read_selection)
  if [ "$SELECTION" = system-default ]; then
    pfs_remove_font_root || true
    pfs_guard_clear
    pfs_write_state state=inactive reason=system-default
    pfs_log "System Default selected; stock fonts are used"
    return 0
  fi
  if ! pfs_validate_targets; then
    pfs_write_state state=inactive reason=invalid-layout
    pfs_log "supported target state is invalid; redirect skipped"
    return 0
  fi
  if pfs_guard_tripped; then
    pfs_write_state state=guard-tripped reason=boot-guard
    pfs_log "boot guard tripped; redirect skipped until a font is applied again"
    return 0
  fi
  if ! pfs_resolve_verified "$SELECTION"; then
    pfs_write_state state=failed reason=font-invalid "font=$SELECTION"
    pfs_log "selected font $SELECTION failed verification; redirect skipped"
    return 0
  fi
  # Nothing is bound yet this boot, so the current generation's XML can be
  # regenerated from the (possibly updated) ROM files.
  if ! pfs_prepare_redirect rebuild; then
    pfs_write_state state=failed reason=prepare-failed "font=$SELECTION"
    pfs_log "redirect preparation failed; stock fonts remain"
    return 0
  fi
  pfs_gc_generations "$PFS_GENERATION" || true
  pfs_guard_enter || true
  pfs_write_state state=waiting "generation=$PFS_GENERATION" "font=$SELECTION"
  pfs_log "prepared gen $PFS_GENERATION for $SELECTION; starting watcher"
  pfs_launch_watcher
}

stage_service() {
  STATE=$(pfs_state_get state 2>/dev/null) || STATE=""
  case "$STATE" in
    waiting|bound)
      if ! pfs_watcher_running; then
        pfs_log "watcher missing at service stage; relaunching"
        if [ "$STATE" = bound ]; then
          pfs_launch_watcher "$(pfs_state_get ss_pid 2>/dev/null)"
        else
          pfs_launch_watcher
        fi
      fi
      ;;
  esac
  # Fallback for managers that do not run boot-completed.sh. Verification is
  # idempotent per boot and never runs on a boot that did not complete.
  (
    WAITED=0
    while [ "$WAITED" -lt 600 ]; do
      pfs_boot_completed && break
      sleep 5
      WAITED=$((WAITED + 5))
    done
    pfs_boot_completed || exit 0
    sleep 20
    sh "$PFS_DIR/scripts/boot-tasks.sh" boot-completed
  ) </dev/null >/dev/null 2>&1 6>&- 7>&- 8>&- 9>&- &
}

# Repairs a bind that came too late: bind, rebuild the font map, release the
# bind, restart the UI, and confirm the new SystemUI received the generation.
repair_late_bind() {
  if ! pfs_bind_all "$SS" "$GENERATION" || ! pfs_restart_font_service \
    || ! pfs_dump_has_generation "$GENERATION"; then
    rollback "repair-failed"
    return
  fi
  pfs_unbind_all "$SS" || pfs_log "could not release the bind in system_server $SS"
  OLD_UI=$(pfs_pid_of com.android.systemui)
  pfs_restart_ui
  NEW_UI=$(pfs_wait_new_systemui "$OLD_UI" "${PFS_UI_WAIT:-30}") || NEW_UI=""
  SERVED=$(pfs_served_map_state "$NEW_UI" "$GENERATION")
  if [ "$SERVED" = stock ]; then
    rollback "repair-not-served"
    return
  fi
  FONT_ID=$(pfs_font_for_generation "$GENERATION" 2>/dev/null) || FONT_ID=unknown
  pfs_write_state state=verified mode=restarted "ss_pid=$SS" "generation=$GENERATION" \
    "font=$FONT_ID" "served_check=$SERVED"
  pfs_log "repaired late redirect with a font-service restart (gen $GENERATION, served check $SERVED)"
}

rollback() {
  pfs_unbind_all "$SS" || true
  pfs_restart_font_service || true
  pfs_restart_ui
  pfs_write_state state=failed "reason=$1" "ss_pid=$SS" "generation=$GENERATION"
  pfs_log "redirect rolled back ($1); stock fonts restored"
}

stage_boot_completed() {
  pfs_boot_completed || exit 0
  pfs_ensure_runtime_dir || exit 0
  exec 6>>"$PFS_RUNTIME_DIR/boot-completed.lock" || exit 0
  flock -n 6 || exit 0
  [ ! -e "$PFS_RUNTIME_DIR/boot-completed.done" ] || exit 0

  STATE=$(pfs_state_get state 2>/dev/null) || STATE=""
  REASON=$(pfs_state_get reason 2>/dev/null) || REASON=""
  case "$STATE" in
    waiting|bound) ;;
    failed) [ "$REASON" = bind-failed ] || STATE=done ;;
    *) STATE=done ;;
  esac
  if [ "$STATE" = done ]; then
    # Nothing to verify. A completed boot clears the guard unless it tripped.
    [ "$(pfs_state_get state 2>/dev/null)" = guard-tripped ] || pfs_guard_clear
    : >"$PFS_RUNTIME_DIR/boot-completed.done"
    return 0
  fi

  # Serialize with Apply / Apply now; give up quietly if a user operation is
  # still running after a minute, since it settles the state itself.
  if ! pfs_wait_lock "$LOCK_FILE" 60; then
    pfs_guard_clear
    : >"$PFS_RUNTIME_DIR/boot-completed.done"
    return 0
  fi

  SS=$(pfs_pid_of system_server)
  GENERATION=$(pfs_current_generation 2>/dev/null) || GENERATION=""
  STATE_GENERATION=$(pfs_state_get generation 2>/dev/null) || STATE_GENERATION=""
  BOUND_PID=$(pfs_state_get ss_pid 2>/dev/null) || BOUND_PID=""
  FONT_SERVICE=$(pfs_state_get font_service_at_bind 2>/dev/null) || FONT_SERVICE=""
  SS_AGE=$(pfs_state_get ss_age_at_bind 2>/dev/null) || SS_AGE=""
  case "$SS_AGE" in ''|*[!0-9]*) SS_AGE=999 ;; esac

  if [ "$STATE" = bound ] && [ -n "$SS" ] && [ "$BOUND_PID" = "$SS" ] && [ -n "$STATE_GENERATION" ]; then
    GENERATION=$STATE_GENERATION
    SS_MAP=$(pfs_state_get ss_map 2>/dev/null) || SS_MAP=""
    # The map SystemUI received is the ground truth for what apps were served;
    # system_server's own copy of the boot map stands in when it is unreadable.
    SERVED=$(pfs_served_map_state "$(pfs_pid_of com.android.systemui)" "$GENERATION")
    if [ "$SERVED" = served ] || { [ "$SERVED" = unknown ] && { [ "$SS_MAP" = served ] \
      || { [ "$FONT_SERVICE" = absent ] && [ "$SS_AGE" -le "$PFS_TRUST_AGE" ]; }; }; }; then
      FONT_ID=$(pfs_font_for_generation "$GENERATION" 2>/dev/null) || FONT_ID=unknown
      pfs_write_state state=verified mode=boot "ss_pid=$SS" "generation=$GENERATION" \
        "font=$FONT_ID" "font_service_at_bind=$FONT_SERVICE" "ss_age_at_bind=$SS_AGE" \
        "ss_map=${SS_MAP:-unknown}" "served_check=$SERVED"
      pfs_log "verified boot-time redirect (gen $GENERATION, font $FONT_ID, served check $SERVED)"
    else
      repair_late_bind
    fi
  elif [ -n "$SS" ] && [ -n "$GENERATION" ] && pfs_xml_ready "$GENERATION" \
    && [ "$(pfs_read_selection)" != system-default ]; then
    # The watcher never bound in time (or failed): bind now and rebuild.
    repair_late_bind
  fi
  # The bind is needed only while the font service parses the XML.
  if [ -n "$SS" ] && pfs_any_bind_present "$SS"; then
    pfs_unbind_all "$SS" || pfs_log "could not release the bind in system_server $SS"
  fi
  pfs_release_lock "$LOCK_FILE"
  pfs_guard_clear
  : >"$PFS_RUNTIME_DIR/boot-completed.done"
}

case "$MODE" in
  post-fs-data) stage_post_fs_data ;;
  service) stage_service ;;
  boot-completed) stage_boot_completed ;;
  *) echo "usage: $0 post-fs-data|service|boot-completed" >&2; exit 2 ;;
esac
exit 0
