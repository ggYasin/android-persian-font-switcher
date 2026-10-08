#!/usr/bin/env sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SANDBOX=$(mktemp -d)
trap 'rm -rf -- "$SANDBOX"' EXIT HUP INT TERM

. "$SCRIPT_DIR/redirect_fixture.sh"
pfs_fixture_init "$SANDBOX"

run() {
  pfs_fixture_env PFS_SKIP_KSU_CONFIG=1 "$@"
}

boot_stage() {
  run PFS_WATCH_FAST=0.01 PFS_WATCH_SLOW=0.01 PFS_WATCH_MAX_LOOPS="${WATCH_LOOPS:-20}" \
    sh "$MODULE/scripts/boot-tasks.sh" "$1"
}

watch() {
  run PFS_WATCH_FAST=0.01 PFS_WATCH_SLOW=0.01 PFS_WATCH_MAX_LOOPS="${WATCH_LOOPS:-20}" \
    sh "$MODULE/scripts/redirect-watcher.sh" "$@"
}

state() {
  sed -n "s/^$1=//p" "$MODULE/runtime/redirect.state"
}

status() {
  run sh "$MODULE/scripts/get-status.sh"
}

fail() {
  echo "$*" >&2
  exit 1
}

wait_for_state() {
  WAITED=0
  until [ "$(state state 2>/dev/null)" = "$1" ]; do
    WAITED=$((WAITED + 1))
    [ "$WAITED" -lt 400 ] || { cat "$MODULE/runtime/redirect.state" >&2; fail "Timed out waiting for state $1"; }
    sleep 0.05
  done
}

wait_for_watcher_exit() {
  WATCHER_PID=$(cat "$MODULE/runtime/watcher.pid" 2>/dev/null || true)
  WAITED=0
  while [ -n "$WATCHER_PID" ] && kill -0 "$WATCHER_PID" 2>/dev/null; do
    WAITED=$((WAITED + 1))
    [ "$WAITED" -lt 400 ] || fail "Watcher did not exit"
    sleep 0.05
  done
}

reset_boot() {
  : >"$CALLS"
  rm -f "$MODULE/runtime/boot-completed.done"
}

# First line number of a logged call matching an extended regex.
call_line() {
  grep -n -E "$1" "$CALLS" | sed -n '1p' | cut -d: -f1
}

# Asserts that no bind of this module is left in a process's namespace.
no_bind_left() {
  if grep -q persian_font_switcher "$PROC/$1/mountinfo" 2>/dev/null; then
    fail "$2"
  fi
}

no_nsenter() {
  if grep -q '^nsenter' "$CALLS"; then
    fail "$1"
  fi
}

run sh "$MODULE/scripts/apply-font.sh" samim | grep -q '^status=ok$'
GEN=$(sed -n '1p' "$FONT_ROOT/generation")

# The patch changes only the four file-name tokens in both XML formats.
for XML in font_fallback.xml fonts.xml; do
  REVERTED="$SANDBOX/$XML.reverted"
  sed "s|\.\./\.\.$FONT_ROOT/gen/$GEN/||g" "$FONT_ROOT/xml/$GEN/$XML" >"$REVERTED"
  cmp "$SYSTEM/etc/$XML" "$REVERTED"
  [ "$(grep -c "gen/$GEN/NotoNaskhArabic" "$FONT_ROOT/xml/$GEN/$XML")" -eq 4 ]
done
cmp "$MODULE/assets/fonts/samim/regular.ttf" "$FONT_ROOT/gen/$GEN/NotoNaskhArabicUI-Regular.ttf"
grep -q "^chcon u:object_r:font_data_file:s0 $FONT_ROOT/gen/.stage.[0-9]*/NotoNaskhArabicUI-Regular.ttf$" "$CALLS"
grep -q "^chown 1000:1000 $FONT_ROOT/xml/.stage.[0-9]*/font_fallback.xml$" "$CALLS"
[ "$(stat -c '%a' "$FONT_ROOT/gen/$GEN/NotoNaskhArabicUI-Regular.ttf")" = 644 ]
[ "$(stat -c '%a' "$FONT_ROOT/gen/$GEN")" = 711 ]
[ "$(stat -c '%a' "$FONT_ROOT/xml/$GEN")" = 711 ]
[ "$(stat -c '%a' "$FONT_ROOT/xml/$GEN/font_fallback.xml")" = 640 ]

# post-fs-data regenerates the XML from the ROM, removes stale generations,
# arms the guard, and starts a detached watcher that binds nothing without a
# system_server.
mkdir -p "$FONT_ROOT/gen/99" "$FONT_ROOT/xml/99" "$FONT_ROOT/gen/.stage.1234"
reset_boot
WATCH_LOOPS=5 boot_stage post-fs-data
[ "$(state state)" = waiting ]
[ "$(state generation)" = "$GEN" ]
[ ! -e "$FONT_ROOT/gen/99" ] && [ ! -e "$FONT_ROOT/xml/99" ] && [ ! -e "$FONT_ROOT/gen/.stage.1234" ]
[ -d "$FONT_ROOT/gen/$GEN" ] && [ -d "$FONT_ROOT/xml/$GEN" ]
[ "$(sed -n '1p' "$MODULE/state/boot-guard")" = 1 ]
wait_for_watcher_exit
[ "$(state state)" = waiting ]
no_nsenter "Watcher entered a namespace without system_server"

# A system_server still sharing zygote's or init's namespace is never entered,
# and neither is one whose zygote namespace cannot be read.
pfs_fixture_system_server 400 2
WATCH_LOOPS=5 watch
no_nsenter "Watcher mounted into zygote's namespace"
pfs_fixture_system_server 400 1
WATCH_LOOPS=5 watch
no_nsenter "Watcher mounted into init's namespace"
pfs_fixture_system_server 400 3
mv "$PROC/300" "$PROC/300.hidden"
WATCH_LOOPS=5 watch
no_nsenter "Watcher trusted an unreadable zygote namespace"
mv "$PROC/300.hidden" "$PROC/300"

# The watcher binds both XML files, waits for system_server's own copy of the
# finished font map, and then releases its binds: apps that NeoZygisk does not
# hide copy system_server's live mounts. Another module's mount on the same
# path is kept beneath ours and is never mistaken for, or removed as, ours.
pfs_fixture_foreign_bind 400 fonts.xml
pfs_fixture_served 400 "x/system/fonts/../..$FONT_ROOT/gen/$GEN/NotoNaskhArabicUI-Regular.ttfx"
WATCH_LOOPS=5 watch
[ "$(state state)" = bound ]
[ "$(state ss_pid)" = 400 ]
[ "$(state font)" = samim ]
[ "$(state font_service_at_bind)" = absent ]
[ "$(state ss_map)" = served ]
[ "$(state released)" = 1 ]
[ "$(grep -c 'nsenter -t 400 -m -- mount -o bind' "$CALLS")" -eq 2 ]
[ "$(grep -c 'nsenter -t 400 -m -- umount' "$CALLS")" -eq 2 ]
[ "$(grep -n 'nsenter -t 400 -m -- mount -o bind' "$CALLS" | tail -n 1 | cut -d: -f1)" \
  -lt "$(grep -n 'nsenter -t 400 -m -- umount' "$CALLS" | sed -n '1p' | cut -d: -f1)" ]
if grep -q persian_font_switcher "$PROC/400/mountinfo"; then
  fail "The bind outlived the font map build"
fi
grep -q ' /adb/modules/other/system/etc/fonts.xml /system/etc/fonts.xml ' "$PROC/400/mountinfo"
for OTHER in 1 300; do
  if grep -q '/system/etc/font' "$PROC/$OTHER/mountinfo" 2>/dev/null; then
    fail "Bind leaked into namespace of pid $OTHER"
  fi
done
grep -q 'released bind in system_server 400 (its font map: served)' "$MODULE/runtime/events.log"

# Without a readable map the bind is still released once the wait ends.
rm -rf "$PROC/400/maps" "$PROC/400/map_files"
: >"$CALLS"
pfs_fixture_state state=waiting "generation=$GEN" font=samim
WATCH_LOOPS=5 watch
[ "$(state ss_map)" = unknown ]
[ "$(state released)" = 1 ]
if grep -q persian_font_switcher "$PROC/400/mountinfo"; then
  fail "The bind was kept after an unreadable font map"
fi

# Back to a boot whose map was built from the bind, for the checks below.
pfs_fixture_state state=waiting "generation=$GEN" font=samim
pfs_fixture_served 400 "x/system/fonts/../..$FONT_ROOT/gen/$GEN/NotoNaskhArabicUI-Regular.ttfx"
WATCH_LOOPS=5 watch
[ "$(state ss_map)" = served ]

# Boot completion never runs on a boot that did not complete.
reset_boot
PFS_TEST_BOOT_COMPLETED=0 boot_stage boot-completed
[ "$(state state)" = bound ]
[ -e "$MODULE/state/boot-guard" ]

# With the served map readable, it is the ground truth.
pfs_fixture_process com.android.systemui 500 7
pfs_fixture_served 500 "x/system/fonts/../..$FONT_ROOT/gen/$GEN/NotoNaskhArabicUI-Regular.ttfx"
reset_boot
boot_stage boot-completed
[ "$(state state)" = verified ]
[ "$(state mode)" = boot ]
[ "$(state served_check)" = served ]
[ ! -e "$MODULE/state/boot-guard" ]
if grep -q '^cmd font restart' "$CALLS"; then
  fail "A served boot-time bind restarted the font service"
fi
STATUS=$(status)
printf '%s\n' "$STATUS" | grep -q '^active=samim$'
printf '%s\n' "$STATUS" | grep -q '^restart_required=false$'
# Verification runs once per boot.
pfs_fixture_state state=waiting "generation=$GEN" font=samim
boot_stage boot-completed
[ "$(state state)" = waiting ]

# A bind whose map SystemUI did not receive is repaired.
reset_boot
pfs_fixture_state state=bound ss_pid=400 "generation=$GEN" font=samim font_service_at_bind=absent ss_age_at_bind=1
pfs_fixture_served 500 "x/system/fonts/NotoNaskhArabicUI-Regular.ttfx"
boot_stage boot-completed
[ "$(state state)" = verified ]
[ "$(state mode)" = restarted ]
grep -q '^cmd font restart' "$CALLS"
grep -q '^kill 500' "$CALLS"
grep -q '^am force-stop com.android.launcher3' "$CALLS"

# The served check reads the font map itself, never a larger JIT cache or a
# writable region that happens to contain the same names.
served_probe() {
  run sh -c '. "$PFS_MODULE_DIR/scripts/lib.sh"; pfs_served_map_state 500 "$1"' sh "$GEN"
}
pfs_fixture_served 500 "x/system/fonts/NotoNaskhArabicUI-Regular.ttfx" \
  "x/system/fonts/../..$FONT_ROOT/gen/$GEN/NotoNaskhArabicUI-Regular.ttfx"
[ "$(served_probe)" = stock ] || fail "The served check trusted a JIT cache or writable region"
pfs_fixture_served 500 "x/system/fonts/../..$FONT_ROOT/gen/$GEN/NotoNaskhArabicUI-Regular.ttfx" \
  "x/system/fonts/NotoNaskhArabicUI-Regular.ttfx"
[ "$(served_probe)" = served ] || fail "The served check missed the font map"

# Without a readable map, a young system_server and an unpublished font
# service are trusted; an old one is not.
rm -rf "$PROC/500/maps" "$PROC/500/map_files"
reset_boot
pfs_fixture_state state=bound ss_pid=400 "generation=$GEN" font=samim font_service_at_bind=absent ss_age_at_bind=1
boot_stage boot-completed
[ "$(state mode)" = boot ]
[ "$(state served_check)" = unknown ]
reset_boot
pfs_fixture_state state=bound ss_pid=400 "generation=$GEN" font=samim font_service_at_bind=absent ss_age_at_bind=9
boot_stage boot-completed
[ "$(state mode)" = restarted ]
printf '%s\n' "" >"$PIDS/com.android.systemui"

# A lost early race is repaired: bind on top of a foreign mount, rebuild the
# map, restart the UI.
reset_boot
pfs_fixture_unbind 400 font_fallback.xml
pfs_fixture_unbind 400 fonts.xml
pfs_fixture_foreign_bind 400 fonts.xml
pfs_fixture_state state=waiting "generation=$GEN" font=samim
boot_stage boot-completed
[ "$(state state)" = verified ]
[ "$(state mode)" = restarted ]
# Bound only for the rebuild: bind, rebuild, release, then restart the UI.
[ "$(grep -c 'nsenter -t 400 -m -- mount -o bind' "$CALLS")" -eq 2 ]
[ "$(call_line 'mount -o bind')" -lt "$(call_line '^cmd font restart')" ]
[ "$(call_line '^cmd font restart')" -lt "$(call_line 'nsenter -t 400 -m -- umount')" ]
[ "$(call_line 'nsenter -t 400 -m -- umount')" -lt "$(call_line '^am force-stop')" ]
no_bind_left 400 "The repair left its bind in system_server"
grep -q ' /adb/modules/other/system/etc/fonts.xml /system/etc/fonts.xml ' "$PROC/400/mountinfo"

# A patched config the font service does not resolve during a repair is
# rolled back, and only this module's binds are removed.
reset_boot
pfs_fixture_state state=bound ss_pid=400 "generation=$GEN" font=samim font_service_at_bind=present ss_age_at_bind=9
PFS_TEST_DUMP_BROKEN=1 boot_stage boot-completed
[ "$(state state)" = failed ]
[ "$(state reason)" = repair-failed ]
if pfs_fixture_bound 400 font_fallback.xml || pfs_fixture_bound 400 fonts.xml; then
  fail "A mismatched config remained bound"
fi
grep -q ' /adb/modules/other/system/etc/fonts.xml /system/etc/fonts.xml ' "$PROC/400/mountinfo" \
  || fail "Rollback removed another module's mount"
grep -q '^cmd font restart' "$CALLS"
status | grep -q '^active=system-default$'

# The watcher stops instead of binding when System Default is selected.
run sh "$MODULE/scripts/apply-font.sh" system-default >/dev/null
: >"$CALLS"
pfs_fixture_system_server 401 4
WATCH_LOOPS=5 watch
no_nsenter "Watcher bound while System Default was selected"

# System Default at boot removes all staged data and binds nothing.
boot_stage post-fs-data
[ "$(state state)" = inactive ]
[ ! -e "$FONT_ROOT" ]
[ ! -e "$MODULE/state/boot-guard" ]

# The boot guard skips activation after two boots that never completed.
run sh "$MODULE/scripts/apply-font.sh" vazirmatn >/dev/null
GEN=$(sed -n '1p' "$FONT_ROOT/generation")
printf '%s\n' 2 >"$MODULE/state/boot-guard"
boot_stage post-fs-data
[ "$(state state)" = guard-tripped ]
status | grep -q '^boot_guard=tripped$'
reset_boot
boot_stage boot-completed
[ "$(sed -n '1p' "$MODULE/state/boot-guard")" = 2 ]
run sh "$MODULE/scripts/apply-font.sh" vazirmatn >/dev/null
[ ! -e "$MODULE/state/boot-guard" ]

# A disabled module's watcher exits without binding.
: >"$MODULE/disable"
: >"$CALLS"
pfs_fixture_system_server 402 5
WATCH_LOOPS=5 watch
no_nsenter "Watcher bound for a disabled module"
rm -f "$MODULE/disable"

# The resident watcher rebinds a restarted system_server. A young successor
# with an unpublished font service is trusted; a late one gets a rebuild.
boot_stage post-fs-data
wait_for_watcher_exit
pfs_fixture_system_server 403 6
WATCH_LOOPS=5 watch
[ "$(state ss_pid)" = 403 ]
rm -rf "$PROC/403"
pfs_fixture_system_server 404 8
pfs_fixture_start 404 1200
PFS_QUICK_DEATH_SECONDS=0 WATCH_LOOPS=3 watch 403
grep -q 'nsenter -t 404 -m -- mount -o bind' "$CALLS"
no_bind_left 404 "A rebind outlived the successor's font map build"
[ "$(state state)" = verified ]
[ "$(state mode)" = rebound ]
rm -rf "$PROC/404"
: >"$CALLS"
pfs_fixture_system_server 405 9
printf '%s\n' 777 >"$PIDS/com.android.systemui"
PFS_TEST_FONT_SERVICE=found PFS_QUICK_DEATH_SECONDS=0 WATCH_LOOPS=3 watch 404
[ "$(grep -c 'nsenter -t 405 -m -- mount -o bind' "$CALLS")" -eq 4 ]
no_bind_left 405 "The rebuild left its bind in system_server"
[ "$(state state)" = verified ]
[ "$(state mode)" = restarted ]
grep -q '^cmd font restart' "$CALLS"
grep -q '^kill 777' "$CALLS"
# A successor whose own map already holds the generation needs no rebuild,
# even when its font service was published before the bind.
rm -rf "$PROC/405"
: >"$CALLS"
pfs_fixture_system_server 406 14
pfs_fixture_served 406 "x/system/fonts/../..$FONT_ROOT/gen/$GEN/NotoNaskhArabicUI-Regular.ttfx"
PFS_TEST_FONT_SERVICE=found PFS_QUICK_DEATH_SECONDS=0 WATCH_LOOPS=3 watch 405
[ "$(state mode)" = rebound ]
[ "$(state ss_map)" = served ]
if grep -q '^cmd font restart' "$CALLS"; then
  fail "A successor serving the generation was rebuilt"
fi
no_bind_left 406 "A served rebind kept its bind"

# A system_server that keeps dying right after a bind stops the redirect and
# trips the guard for the next boot.
rm -f "$MODULE/runtime/redirect.state"
pfs_fixture_system_server 410 10
run PFS_WATCH_FAST=0.01 PFS_WATCH_SLOW=0.01 PFS_WATCH_MAX_LOOPS=4000 \
  sh "$MODULE/scripts/redirect-watcher.sh" &
LOOP_WATCHER=$!
wait_for_state bound
[ "$(state ss_pid)" = 410 ]
pfs_fixture_system_server 411 11
rm -rf "$PROC/410"
WAITED=0
until [ "$(state ss_pid 2>/dev/null)" = 411 ]; do
  WAITED=$((WAITED + 1))
  [ "$WAITED" -lt 400 ] || fail "Watcher did not rebind the successor"
  sleep 0.05
done
pfs_fixture_system_server 412 12
rm -rf "$PROC/411"
wait "$LOOP_WATCHER"
[ "$(state state)" = guard-tripped ]
[ "$(state reason)" = system-server-restart-loop ]
status | grep -q '^boot_guard=tripped$'
printf '%s\n' "" >"$PIDS/com.android.systemui"
run sh "$MODULE/scripts/apply-font.sh" vazirmatn >/dev/null

# Live apply swaps this module's bind to the new generation and rebuilds.
: >"$CALLS"
rm -f "$MODULE/runtime/redirect.state"
pfs_fixture_system_server 420 13
pfs_fixture_bind 420 font_fallback.xml "$GEN"
run sh "$MODULE/scripts/apply-font.sh" estedad >/dev/null
NEW_GEN=$(sed -n '1p' "$FONT_ROOT/generation")
[ "$NEW_GEN" -gt "$GEN" ]
[ "$(pfs_fixture_bound_generation 420 font_fallback.xml)" = "$GEN" ]
LIVE=$(run PFS_WATCH_MAX_LOOPS=2 PFS_WATCH_SLOW=0.01 sh "$MODULE/scripts/live-apply.sh")
printf '%s\n' "$LIVE" | grep -q '^status=ok$'
printf '%s\n' "$LIVE" | grep -q '^active=estedad$'
[ "$(state state)" = verified ]
[ "$(state mode)" = live ]
grep -q "nsenter -t 420 -m -- mount -o bind $FONT_ROOT/xml/$NEW_GEN/font_fallback.xml /system/etc/font_fallback.xml" "$CALLS"
[ "$(call_line '^cmd font restart')" -lt "$(call_line "nsenter -t 420 -m -- umount /system/etc/fonts.xml")" ]
[ "$(grep -c ' /system/etc/font_fallback.xml ' "$PROC/420/mountinfo")" -eq 0 ]
no_bind_left 420 "Live apply left its bind in system_server"
grep -q '^cmd font restart' "$CALLS"
status | grep -q '^active=estedad$'
wait_for_watcher_exit

# A live apply the font service rejects restores stock and records failure.
run sh "$MODULE/scripts/apply-font.sh" shabnam >/dev/null
if PFS_TEST_DUMP_BROKEN=1 run sh "$MODULE/scripts/live-apply.sh" >/dev/null 2>&1; then
  fail "Live apply accepted a configuration the font service rejected"
fi
[ "$(state state)" = failed ]
if pfs_fixture_bound 420 font_fallback.xml; then
  fail "Rejected live apply left a bind"
fi
status | grep -q '^active=system-default$'

# Live System Default removes the bind from system_server.
run sh "$MODULE/scripts/apply-font.sh" estedad >/dev/null
run PFS_WATCH_MAX_LOOPS=1 sh "$MODULE/scripts/live-apply.sh" >/dev/null
wait_for_watcher_exit
run sh "$MODULE/scripts/apply-font.sh" system-default >/dev/null
LIVE_DEFAULT=$(run sh "$MODULE/scripts/live-apply.sh")
printf '%s\n' "$LIVE_DEFAULT" | grep -q '^active=system-default$'
if pfs_fixture_bound 420 font_fallback.xml; then
  fail "Live System Default left the bind in place"
fi
status | grep -q '^active=system-default$'

# Before the first unlock HOME resolves to Settings' FallbackHome; the
# launcher is found through the HOME role, and Settings is never stopped.
: >"$CALLS"
PFS_TEST_HOME_RESOLVE=com.android.settings/.FallbackHome run sh -c \
  '. "$PFS_MODULE_DIR/scripts/lib.sh"; pfs_restart_ui'
grep -q '^am force-stop com.android.launcher3$' "$CALLS"
: >"$CALLS"
PFS_TEST_HOME_ROLE= PFS_TEST_HOME_RESOLVE=com.android.settings/.FallbackHome run sh -c \
  '. "$PFS_MODULE_DIR/scripts/lib.sh"; pfs_restart_ui'
if grep -q '^am force-stop' "$CALLS"; then
  fail "The UI restart stopped Settings' FallbackHome"
fi

# Live apply refuses a system_server it cannot isolate.
run sh "$MODULE/scripts/apply-font.sh" estedad >/dev/null
pfs_fixture_system_server 430 2
if run sh "$MODULE/scripts/live-apply.sh" >/dev/null 2>&1; then
  fail "Live apply accepted a system_server in zygote's namespace"
fi

# Uninstall removes only the staged copies.
mkdir -p "$SANDBOX/uninstall-root/fonts/persian_font_switcher/gen/1"
sed "s|/data/fonts/persian_font_switcher|$SANDBOX/uninstall-root/fonts/persian_font_switcher|" \
  "$SCRIPT_DIR/../uninstall.sh" >"$SANDBOX/uninstall-test.sh"
sh "$SANDBOX/uninstall-test.sh"
[ ! -e "$SANDBOX/uninstall-root/fonts/persian_font_switcher" ]
[ -d "$SANDBOX/uninstall-root/fonts" ]

echo "Mount-free redirect tests passed"
