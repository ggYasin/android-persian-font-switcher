#!/usr/bin/env sh
# Shared sandbox for the redirect tests: a module tree, a fake ROM with both
# font XML formats, a fake /proc, and stubs for the Android tools the module
# drives. Source it, then call pfs_fixture_init SANDBOX.

pfs_fixture_init() {
  FIXTURE_ROOT=$1
  FIXTURE_PROJECT=${PFS_FIXTURE_PROJECT:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}
  MODULE="$FIXTURE_ROOT/module"
  ADB="$FIXTURE_ROOT/adb"
  DATA="$FIXTURE_ROOT/data"
  FONT_ROOT="$FIXTURE_ROOT/fonts/persian_font_switcher"
  SYSTEM="$FIXTURE_ROOT/system"
  PROC="$FIXTURE_ROOT/proc"
  BIN="$FIXTURE_ROOT/bin"
  PIDS="$FIXTURE_ROOT/pids"
  CALLS="$FIXTURE_ROOT/calls.log"
  mkdir -p "$MODULE/scripts" "$MODULE/webroot" "$MODULE/state" "$ADB/modules" \
    "$FIXTURE_ROOT/fonts" "$SYSTEM/etc" "$SYSTEM/fonts" "$PROC/1/ns" "$BIN" "$PIDS"
  cp -R "$FIXTURE_PROJECT/assets" "$MODULE/assets"
  cp "$FIXTURE_PROJECT/scripts/"*.sh "$MODULE/scripts/"
  cp "$FIXTURE_PROJECT/webroot/font-manifest.json" "$MODULE/webroot/"
  cp "$FIXTURE_PROJECT/state/supported-targets" "$FIXTURE_PROJECT/state/selected-font" "$MODULE/state/"
  : >"$CALLS"

  cat >"$SYSTEM/etc/font_fallback.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<familyset>
  <family name="sans-serif">
    <font weight="400" style="normal">Roboto-Regular.ttf</font>
  </family>
  <family lang="und-Arab" variant="elegant">
    <font weight="400" style="normal" postScriptName="NotoNaskhArabic">NotoNaskhArabic-Regular.ttf</font>
    <font weight="700" style="normal">NotoNaskhArabic-Bold.ttf</font>
  </family>
  <family lang="und-Arab" variant="compact">
    <font weight="400" style="normal" postScriptName="NotoNaskhArabicUI">NotoNaskhArabicUI-Regular.ttf</font>
    <font weight="700" style="normal">NotoNaskhArabicUI-Bold.ttf</font>
  </family>
  <family lang="und-Ethi">
    <font weight="400" style="normal">NotoSansEthiopic-VF.ttf</font>
  </family>
</familyset>
EOF
  cat >"$SYSTEM/etc/fonts.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<familyset version="23">
    <!-- fallback fonts -->
    <family lang="und-Arab" variant="elegant">
        <font weight="400" style="normal" postScriptName="NotoNaskhArabic">
            NotoNaskhArabic-Regular.ttf
        </font>
        <font weight="700" style="normal">NotoNaskhArabic-Bold.ttf</font>
    </family>
    <family lang="und-Arab" variant="compact">
        <font weight="400" style="normal" postScriptName="NotoNaskhArabicUI">
            NotoNaskhArabicUI-Regular.ttf
        </font>
        <font weight="700" style="normal">NotoNaskhArabicUI-Bold.ttf</font>
    </family>
</familyset>
EOF
  for FIXTURE_TARGET in NotoNaskhArabicUI-Regular.ttf NotoNaskhArabicUI-Bold.ttf \
    NotoNaskhArabic-Regular.ttf NotoNaskhArabic-Bold.ttf; do
    printf '%s' stock >"$SYSTEM/fonts/$FIXTURE_TARGET"
  done

  printf '%s\n' '12.50 40.00' >"$PROC/uptime"
  ln -sf 'mnt:[1]' "$PROC/1/ns/mnt"
  pfs_fixture_process zygote64 300 2

  for FIXTURE_STUB in chcon chown sync log am kill; do
    printf '%s\n' '#!/usr/bin/env sh' "printf '%s %s\\n' $FIXTURE_STUB \"\$*\" >>\"\$PFS_TEST_CALLS\"" 'exit 0' \
      >"$BIN/$FIXTURE_STUB"
  done
  cat >"$BIN/pidof" <<'EOF'
#!/usr/bin/env sh
[ -f "$PFS_TEST_PIDS/$1" ] || exit 1
cat "$PFS_TEST_PIDS/$1"
EOF
  cat >"$BIN/getprop" <<'EOF'
#!/usr/bin/env sh
printf '%s\n' "${PFS_TEST_BOOT_COMPLETED:-1}"
EOF
  cat >"$BIN/service" <<'EOF'
#!/usr/bin/env sh
printf 'Service %s: %s\n' "$2" "${PFS_TEST_FONT_SERVICE:-not found}"
EOF
  cat >"$BIN/cmd" <<'EOF'
#!/usr/bin/env sh
printf 'cmd %s\n' "$*" >>"$PFS_TEST_CALLS"
case "$1 $2" in
  "font restart") exit "${PFS_TEST_FONT_RESTART_STATUS:-0}" ;;
  "package resolve-activity")
    printf '%s\n' 'priority=0 preferredOrder=0 match=0x108000' \
      "${PFS_TEST_HOME_RESOLVE:-com.android.launcher3/com.android.launcher3.uioverrides.QuickstepLauncher}" ;;
  "role get-role-holders") printf '%s\n' "${PFS_TEST_HOME_ROLE-com.android.launcher3}" ;;
esac
exit 0
EOF
  # Emulates nsenter into a fake process namespace by editing its mountinfo.
  cat >"$BIN/nsenter" <<'EOF'
#!/usr/bin/env sh
printf 'nsenter %s\n' "$*" >>"$PFS_TEST_CALLS"
[ "$1" = -t ] || exit 2
TARGET_PID=$2
shift 2
[ "$1" = -m ] && shift
[ "$1" = -- ] && shift
MOUNTINFO="$PFS_PROC_ROOT/$TARGET_PID/mountinfo"
case "$1" in
  mount)
    [ "${PFS_TEST_BIND_FAIL:-0}" = 1 ] && exit 32
    [ "$2" = -o ] && [ "$3" = bind ] || exit 2
    [ -f "$4" ] || exit 32
    printf '900 1 253:41 %s %s rw,noatime master:1 - f2fs /dev/block/dm-41 rw\n' "$4" "$5" >>"$MOUNTINFO"
    ;;
  umount)
    # Like umount(8): only the topmost mount on the path goes away.
    LAST=$(awk -v target="$2" '$5 == target { line = NR } END { print line + 0 }' "$MOUNTINFO")
    [ "$LAST" -gt 0 ] || exit 32
    awk -v drop="$LAST" 'NR != drop' "$MOUNTINFO" >"$MOUNTINFO.tmp"
    mv "$MOUNTINFO.tmp" "$MOUNTINFO"
    ;;
  *) exit 2 ;;
esac
EOF
  # Emulates FontManagerService re-parsing whichever XML system_server sees.
  cat >"$BIN/dumpsys" <<'EOF'
#!/usr/bin/env sh
SERVER=$(cat "$PFS_TEST_PIDS/system_server" 2>/dev/null)
XML="$PFS_TEST_SYSTEM_ROOT/etc/font_fallback.xml"
if [ -n "$SERVER" ] && [ "${PFS_TEST_DUMP_BROKEN:-0}" != 1 ]; then
  TOP=$(awk '$5 == "/system/etc/font_fallback.xml" { root = $4 } END { print root }' \
    "$PFS_PROC_ROOT/$SERVER/mountinfo" 2>/dev/null)
  [ -f "$TOP" ] && XML=$TOP
fi
grep -o '[^>[:space:]]*NotoNaskhArabic[A-Za-z-]*\.ttf' "$XML" | while IFS= read -r NAME; do
  printf '    style = FontStyle { weight=400, slant=0}, path = /system/fonts/%s, rev=1.0\n' "$NAME"
done
EOF
  chmod 0755 "$BIN/"*
}

pfs_fixture_process() {
  printf '%s\n' "$2" >"$PIDS/$1"
  mkdir -p "$PROC/$2/ns"
  ln -sf "mnt:[$3]" "$PROC/$2/ns/mnt"
  [ -f "$PROC/$2/mountinfo" ] \
    || printf '%s\n' '22 1 253:5 / / ro,noatime master:1 - ext4 /dev/block/dm-5 ro' >"$PROC/$2/mountinfo"
}

pfs_fixture_system_server() {
  pfs_fixture_process system_server "$1" "${2:-3}"
}

# pfs_fixture_bind PID NAME GENERATION
pfs_fixture_bind() {
  printf '900 1 253:41 %s /system/etc/%s rw,noatime master:1 - f2fs /dev/block/dm-41 rw\n' \
    "$FONT_ROOT/xml/$3/$2" "$2" >>"$PROC/$1/mountinfo"
}

# Another module's mount on the same path, as magic mount would create it.
pfs_fixture_foreign_bind() {
  printf '800 1 253:41 /adb/modules/other/system/etc/%s /system/etc/%s ro - f2fs /dev/block/dm-41 rw\n' \
    "$2" "$2" >>"$PROC/$1/mountinfo"
}

pfs_fixture_bound_generation() {
  awk -v target="/system/etc/$2" '$5 == target { root = $4 } END { print root }' "$PROC/$1/mountinfo" \
    | sed -n 's|.*/persian_font_switcher/xml/\([0-9]*\)/.*|\1|p'
}

# pfs_fixture_served PID TEXT: the font-map shared memory a process received.
# pfs_fixture_served PID TEXT [DECOY]: the font map holds TEXT, laid out as on
# device (unnamed ashmem among small regions). DECOY goes into a larger JIT
# cache and a writable region, which the served check must ignore.
pfs_fixture_served() {
  rm -rf "$PROC/$1/map_files"
  mkdir -p "$PROC/$1/map_files"
  printf '%s\n' \
    '7e00000000-7e02000000 r--s 00000000 00:05 100 /memfd:jit-cache (deleted)' \
    '7f00000000-7f00001000 r--s 00000000 00:01 4241 /dev/ashmem (deleted)' \
    '7f00010000-7f00330000 r--s 00000000 00:01 4242 /dev/ashmem (deleted)' \
    '7f00400000-7f00800000 rw-s 00000000 00:01 4243 /dev/ashmem (deleted)' >"$PROC/$1/maps"
  printf '%s' "${3:-}" >"$PROC/$1/map_files/7e00000000-7e02000000"
  printf '%s' 'x' >"$PROC/$1/map_files/7f00000000-7f00001000"
  printf '%s' "$2" >"$PROC/$1/map_files/7f00010000-7f00330000"
  printf '%s' "${3:-}" >"$PROC/$1/map_files/7f00400000-7f00800000"
}

# pfs_fixture_start PID TICKS: process start time in clock ticks since boot.
pfs_fixture_start() {
  printf '%s (system_server) S 1 1 0 0 -1 0 0 0 0 0 0 0 0 0 20 0 1 0 %s 0 0\n' "$1" "$2" >"$PROC/$1/stat"
}

pfs_fixture_unbind() {
  grep -v " /system/etc/$2 " "$PROC/$1/mountinfo" >"$PROC/$1/mountinfo.tmp" || true
  mv "$PROC/$1/mountinfo.tmp" "$PROC/$1/mountinfo"
}

pfs_fixture_bound() {
  [ -n "$(pfs_fixture_bound_generation "$1" "$2")" ]
}

pfs_fixture_state() {
  mkdir -p "$MODULE/runtime"
  printf '%s\n' "$@" >"$MODULE/runtime/redirect.state"
}

pfs_fixture_env() {
  env PFS_MODULE_DIR="$MODULE" PFS_ADB_ROOT="$ADB" PFS_DATA_DIR="$DATA" \
    PFS_FONT_ROOT="$FONT_ROOT" PFS_TEST_SYSTEM_ROOT="$SYSTEM" PFS_PROC_ROOT="$PROC" \
    PFS_CHCON_BIN="$BIN/chcon" PFS_CHOWN_BIN="$BIN/chown" PFS_NSENTER_BIN="$BIN/nsenter" \
    PFS_PIDOF_BIN="$BIN/pidof" PFS_SERVICE_BIN="$BIN/service" PFS_CMD_BIN="$BIN/cmd" \
    PFS_AM_BIN="$BIN/am" PFS_DUMPSYS_BIN="$BIN/dumpsys" PFS_GETPROP_BIN="$BIN/getprop" \
    PFS_LOG_BIN="$BIN/log" PFS_KILL_BIN="$BIN/kill" PFS_REBUILD_DELAY=0 PFS_UI_WAIT=0 PFS_MAP_POLL=0.01 PFS_MAP_MAX_TICKS="${PFS_FIXTURE_MAP_TICKS:-3}" PFS_TEST_PIDS="$PIDS" PFS_TEST_CALLS="$CALLS" \
    PATH="$BIN:$PATH" "$@"
}
