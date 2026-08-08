#!/usr/bin/env sh
set -eu

if [ "$#" -ne 1 ]; then
  echo "usage: $0 MODULE_ZIP" >&2
  exit 2
fi

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
ARCHIVE=$1
SANDBOX=$(mktemp -d)
trap 'rm -rf -- "$SANDBOX"' EXIT HUP INT TERM

make_fake_rom() {
  TEST_ROOT=$1
  mkdir -p "$TEST_ROOT/system/etc" "$TEST_ROOT/system/fonts" \
    "$TEST_ROOT/data/adb/modules" "$TEST_ROOT/data/adb/modules_update"
  cat >"$TEST_ROOT/system/etc/fonts.xml" <<'EOF'
<familyset>
  <family lang="und-Arab" variant="compact">
    <font>NotoNaskhArabicUI-Regular.ttf</font>
    <font>NotoNaskhArabicUI-Bold.ttf</font>
  </family>
  <family lang="und-Arab" variant="elegant">
    <font>NotoNaskhArabic-Regular.ttf</font>
    <font>NotoNaskhArabic-Bold.ttf</font>
  </family>
</familyset>
EOF
  for TARGET in \
    NotoNaskhArabicUI-Regular.ttf \
    NotoNaskhArabicUI-Bold.ttf \
    NotoNaskhArabic-Regular.ttf \
    NotoNaskhArabic-Bold.ttf
  do
    : >"$TEST_ROOT/system/fonts/$TARGET"
  done
}

make_runner() {
  RUNNER=$1
  cat >"$RUNNER" <<'EOF'
#!/usr/bin/env sh
set -eu

ui_print() {
  printf '%s\n' "$*"
}

abort() {
  printf '%s\n' "$*" >&2
  exit 1
}

set_perm() {
  chmod "$4" "$1"
}

set_perm_recursive() {
  find "$1" -type d -exec chmod "$4" {} +
  find "$1" -type f -exec chmod "$5" {} +
}

. "$MODPATH/customize.sh"
EOF
  chmod 0755 "$RUNNER"
}

run_install_case() {
  CASE_NAME=$1
  CASE_DIR="$SANDBOX/$CASE_NAME"
  MODPATH="$CASE_DIR/module"
  TEST_ROOT="$CASE_DIR/device"
  mkdir -p "$MODPATH"
  unzip -q "$ARCHIVE" -d "$MODPATH"
  make_fake_rom "$TEST_ROOT"
  make_runner "$CASE_DIR/run-customize.sh"

  # Simulate KernelSU Next extracting ordinary ZIP payload scripts as 0644.
  chmod 0644 "$MODPATH/customize.sh" "$MODPATH/scripts/"*.sh

  export MODPATH API=36
  export PFS_TEST_SYSTEM_ROOT="$TEST_ROOT/system"
  export PFS_TEST_ADB_ROOT="$TEST_ROOT/data/adb"
}

run_install_case success
SUCCESS_LOG="$SANDBOX/success.log"
[ "$(stat -c '%a' "$MODPATH/scripts/apply-font.sh")" = "644" ] || {
  echo "Regression precondition failed: apply-font.sh was not 0644 before customize.sh" >&2
  exit 1
}
sh "$SANDBOX/success/run-customize.sh" >"$SUCCESS_LOG" 2>&1
grep -q '^Initial font apply output (exit 0):$' "$SUCCESS_LOG"
grep -q '^  status=ok$' "$SUCCESS_LOG"
grep -q '^  selected=vazirmatn$' "$SUCCESS_LOG"

for SCRIPT in "$MODPATH/customize.sh" "$MODPATH/scripts/"*.sh; do
  [ "$(stat -c '%a' "$SCRIPT")" = "755" ] || {
    echo "Installed runtime script is not 0755: $SCRIPT" >&2
    exit 1
  }
done

cmp "$MODPATH/assets/fonts/vazirmatn/regular.ttf" "$MODPATH/system/fonts/NotoNaskhArabicUI-Regular.ttf"
cmp "$MODPATH/assets/fonts/vazirmatn/regular.ttf" "$MODPATH/system/fonts/NotoNaskhArabic-Regular.ttf"
cmp "$MODPATH/assets/fonts/vazirmatn/bold.ttf" "$MODPATH/system/fonts/NotoNaskhArabicUI-Bold.ttf"
cmp "$MODPATH/assets/fonts/vazirmatn/bold.ttf" "$MODPATH/system/fonts/NotoNaskhArabic-Bold.ttf"
[ ! -e "$MODPATH/state/install-apply.log" ]
[ ! -e "$MODPATH/skip_mount" ]

# A failed apply must expose the trusted script's concrete code/message while
# still aborting installation and leaving skip_mount enabled.
run_install_case diagnostics
[ "$(stat -c '%a' "$MODPATH/scripts/apply-font.sh")" = "644" ] || {
  echo "Diagnostics precondition failed: apply-font.sh was not 0644 before customize.sh" >&2
  exit 1
}
printf '%s' corrupt >"$MODPATH/assets/fonts/vazirmatn/regular.ttf"
DIAGNOSTIC_LOG="$SANDBOX/diagnostics.log"
if sh "$SANDBOX/diagnostics/run-customize.sh" >"$DIAGNOSTIC_LOG" 2>&1; then
  echo "Installer accepted a corrupt initial font" >&2
  exit 1
fi
grep -q '^Initial font apply output (exit 5):$' "$DIAGNOSTIC_LOG"
grep -q '^  code=font-checksum-mismatch$' "$DIAGNOSTIC_LOG"
grep -q '^  message=The selected font failed integrity validation\.$' "$DIAGNOSTIC_LOG"
grep -q "Failed to prepare the initial 'vazirmatn' fallback overlay (exit 5)" "$DIAGNOSTIC_LOG"
[ -e "$MODPATH/skip_mount" ]
[ ! -e "$MODPATH/state/install-apply.log" ]

echo "Installer 0644-permission regression tests passed"
