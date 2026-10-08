#!/system/bin/sh
# Binds the published font XML generation into system_server's private mount
# namespace as soon as system_server has unshared from zygote, before
# FontManagerService builds the font map that apps receive, and removes the
# bind again once that map exists. The bind must not outlive the parse: apps
# that NeoZygisk does not hide copy system_server's live mount namespace. It
# then stays resident with a cheap liveness check so a restarted system_server
# (soft reboot, crash) is covered too. It never mounts in any namespace other
# than system_server's.
#
# Usage: redirect-watcher.sh [already-bound-system_server-pid]

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
. "$SCRIPT_DIR/lib.sh"

FAST=${PFS_WATCH_FAST:-0.1}
SLOW=${PFS_WATCH_SLOW:-2}
FAST_WINDOW=${PFS_WATCH_FAST_WINDOW:-180}
MAX_LOOPS=${PFS_WATCH_MAX_LOOPS:-0}
QUICK_DEATH_SECONDS=${PFS_QUICK_DEATH_SECONDS:-90}

pfs_ensure_runtime_dir || exit 1
exec 8>>"$PFS_RUNTIME_DIR/watcher.lock" || exit 1
flock -n 8 || exit 0

BOUND=${1:-}
case "$BOUND" in *[!0-9]*) BOUND="" ;; esac
BINDS=0
[ -n "$BOUND" ] && BINDS=1
BOUND_AT=$(pfs_uptime_seconds)
QUICK_DEATHS=0
LOOPS=0
FAST_UNTIL=$(($(pfs_uptime_seconds) + FAST_WINDOW))

# Rebuilds the font map once the restarted framework is up, for the case where
# a successor system_server may have built its map before the bind.
rebuild_after_restart() {
  WAITED=0
  while [ "$WAITED" -lt 120 ]; do
    [ -n "$(pfs_pid_of com.android.systemui)" ] && break
    sleep 2
    WAITED=$((WAITED + 2))
  done
  sleep "${PFS_REBUILD_DELAY:-5}"
  if ! pfs_wait_lock "$PFS_DIR/.apply-lock" 60; then
    pfs_log "late font-map rebuild skipped: another font operation holds the lock"
    return 0
  fi
  if [ "$(pfs_pid_of system_server)" = "$2" ] && pfs_bind_all "$2" "$1" && pfs_restart_font_service \
    && pfs_dump_has_generation "$1"; then
    pfs_unbind_all "$2" || pfs_log "could not release the bind in system_server $2"
    pfs_restart_ui
    pfs_write_state state=verified mode=restarted "ss_pid=$2" "generation=$1" "font=$3" \
      "bound_uptime=$4" "binds=$BINDS"
    pfs_log "rebuilt font map after late bind (gen $1, system_server $2)"
  else
    pfs_unbind_all "$2" || true
    pfs_restart_font_service || true
    pfs_write_state state=failed reason=late-rebuild-failed "ss_pid=$2" "generation=$1" "font=$3"
    pfs_log "late font-map rebuild failed (gen $1, system_server $2); stock fonts restored"
  fi
  pfs_release_lock "$PFS_DIR/.apply-lock"
}

# Removes the bind once the boot map exists, unless another operation has
# settled this system_server's record meanwhile (it then releases the bind).
release_bind() {
  if ! pfs_wait_lock "$PFS_DIR/.apply-lock" 30; then
    pfs_log "bind release deferred: another font operation holds the lock"
    return 0
  fi
  if [ "$(pfs_state_get state 2>/dev/null)" = bound ] && [ "$(pfs_state_get ss_pid 2>/dev/null)" = "$1" ]; then
    if pfs_unbind_all "$1"; then
      pfs_update_state "ss_map=$2" released=1 || true
      pfs_log "released bind in system_server $1 (its font map: $2)"
    else
      pfs_update_state "ss_map=$2" released=0 || true
      pfs_log "could not release the bind in system_server $1"
    fi
  fi
  pfs_release_lock "$PFS_DIR/.apply-lock"
}

while :; do
  LOOPS=$((LOOPS + 1))
  if [ "$MAX_LOOPS" -gt 0 ] && [ "$LOOPS" -gt "$MAX_LOOPS" ]; then
    exit 0
  fi
  if [ -e "$PFS_DIR/disable" ] || [ -e "$PFS_DIR/remove" ]; then
    pfs_log "watcher stopping: module disabled or pending removal"
    exit 0
  fi

  NOW=$(pfs_uptime_seconds)
  if [ -n "$BOUND" ]; then
    # Steady state costs one stat per tick; scanning for a successor starts
    # only once the bound system_server is gone.
    if [ -d "$PFS_PROC_ROOT/$BOUND" ]; then
      sleep "$SLOW"
      continue
    fi
    if [ $((NOW - BOUND_AT)) -lt "$QUICK_DEATH_SECONDS" ]; then
      QUICK_DEATHS=$((QUICK_DEATHS + 1))
    else
      QUICK_DEATHS=0
    fi
    if [ "$QUICK_DEATHS" -ge 2 ]; then
      # system_server keeps dying shortly after binding: stop redirecting and
      # keep the next boot on stock fonts too, until a font is applied again.
      pfs_guard_trip || true
      pfs_write_state state=guard-tripped reason=system-server-restart-loop
      pfs_log "system_server died twice shortly after binding; redirect stopped"
      exit 0
    fi
    BOUND=""
    FAST_UNTIL=$((NOW + 60))
  fi
  SS=$(pfs_pid_of system_server)
  if [ -z "$SS" ] || ! pfs_ss_isolated "$SS"; then
    if [ "$NOW" -lt "$FAST_UNTIL" ]; then
      sleep "$FAST"
    else
      sleep "$SLOW"
    fi
    continue
  fi

  # A new isolated system_server: re-check intent only now, because selection
  # validation can hash custom fonts and must stay off the fast polling path.
  SELECTION=$(pfs_read_selection)
  if [ "$SELECTION" = system-default ]; then
    pfs_log "watcher stopping: System Default selected"
    exit 0
  fi
  GENERATION=$(pfs_current_generation 2>/dev/null) || GENERATION=""
  if [ -z "$GENERATION" ] || ! pfs_xml_ready "$GENERATION"; then
    pfs_write_state state=failed reason=prepared-files-missing
    pfs_log "watcher stopping: prepared redirect files are missing"
    exit 0
  fi

  if pfs_font_service_published; then
    FONT_SERVICE=present
  else
    FONT_SERVICE=absent
  fi
  if pfs_bind_all "$SS" "$GENERATION"; then
    BINDS=$((BINDS + 1))
    BOUND=$SS
    BOUND_AT=$(pfs_uptime_seconds)
    SS_AGE=$(pfs_process_age "$SS" 2>/dev/null) || SS_AGE=unknown
    # Identify the font only after the time-critical bind.
    FONT_ID=$(pfs_font_for_generation "$GENERATION" 2>/dev/null) || FONT_ID=unknown
    pfs_write_state state=bound "ss_pid=$SS" "generation=$GENERATION" "font=$FONT_ID" \
      "font_service_at_bind=$FONT_SERVICE" "ss_age_at_bind=$SS_AGE" "bound_uptime=$(pfs_uptime)" "binds=$BINDS"
    pfs_log "bound font XML gen $GENERATION into system_server $SS (age ${SS_AGE}s, font service $FONT_SERVICE, font $FONT_ID)"
    SS_MAP=$(pfs_wait_server_map "$SS" "$GENERATION" "${PFS_MAP_WAIT:-90}")
    release_bind "$SS" "$SS_MAP"
    if [ "$BINDS" -gt 1 ]; then
      # A successor system_server after a soft restart: there is no later
      # boot-completed step, so settle verification here.
      case "$SS_AGE" in ''|*[!0-9]*) SS_AGE=999 ;; esac
      if [ "$SS_MAP" = served ] || { [ "$SS_MAP" = unknown ] && [ "$FONT_SERVICE" = absent ] \
        && [ "$SS_AGE" -le "$PFS_TRUST_AGE" ]; }; then
        pfs_write_state state=verified mode=rebound "ss_pid=$SS" "generation=$GENERATION" "font=$FONT_ID" \
          "font_service_at_bind=$FONT_SERVICE" "ss_age_at_bind=$SS_AGE" "ss_map=$SS_MAP" "binds=$BINDS"
      else
        rebuild_after_restart "$GENERATION" "$SS" "$FONT_ID" "$(pfs_uptime)"
      fi
    fi
  else
    BOUND=$SS
    BOUND_AT=$(pfs_uptime_seconds)
    pfs_write_state state=failed reason=bind-failed "ss_pid=$SS" "generation=$GENERATION"
    pfs_log "bind into system_server $SS failed; stock fonts remain for this boot"
  fi
done
