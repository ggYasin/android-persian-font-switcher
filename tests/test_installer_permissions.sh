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

make_valid_persistent_font() {
  CUSTOM_PARENT="$TEST_ROOT/data/adb/persian_font_switcher/custom-fonts"
  REGULAR_HASH=$(sha256sum "$MODPATH/assets/fonts/mikhak/regular.ttf" | awk '{print $1}')
  BOLD_HASH=$(sha256sum "$MODPATH/assets/fonts/mikhak/bold.ttf" | awk '{print $1}')
  CUSTOM_ID="custom-$(printf '%s' "$REGULAR_HASH" | cut -c1-12)$(printf '%s' "$BOLD_HASH" | cut -c1-12)"
  CUSTOM_DIR="$CUSTOM_PARENT/$CUSTOM_ID"
  mkdir -p "$CUSTOM_DIR"
  cp "$MODPATH/assets/fonts/mikhak/regular.ttf" "$CUSTOM_DIR/regular.ttf"
  cp "$MODPATH/assets/fonts/mikhak/bold.ttf" "$CUSTOM_DIR/bold.ttf"
  printf '%s\n' "$REGULAR_HASH" >"$CUSTOM_DIR/regular.sha256"
  printf '%s\n' "$BOLD_HASH" >"$CUSTOM_DIR/bold.sha256"
  printf '%s\n' 'VGVzdCBQZXJzaXN0ZW50IEZvbnQ=' >"$CUSTOM_DIR/name.b64"
  chmod 0700 "$TEST_ROOT/data/adb/persian_font_switcher" "$CUSTOM_PARENT" "$CUSTOM_DIR"
  chmod 0600 "$CUSTOM_DIR"/*
}

run_install_case no-persistent-data
SUCCESS_LOG="$SANDBOX/success.log"
[ "$(stat -c '%a' "$MODPATH/scripts/apply-font.sh")" = "644" ] || {
  echo "Regression precondition failed: apply-font.sh was not 0644 before customize.sh" >&2
  exit 1
}
sh "$SANDBOX/no-persistent-data/run-customize.sh" >"$SUCCESS_LOG" 2>&1
grep -q '^Custom-font preview restore output (exit 0):$' "$SUCCESS_LOG"
grep -q '^  code=no-custom-data$' "$SUCCESS_LOG"
[ ! -e "$TEST_ROOT/data/adb/persian_font_switcher" ]
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

# A valid persistent custom font survives a module update and gets fresh,
# read-only WebUI preview copies in the newly extracted module tree.
run_install_case valid-persistent-data
make_valid_persistent_font
VALID_ORIGINAL="$CUSTOM_DIR"
VALID_LOG="$SANDBOX/valid-persistent.log"
sh "$SANDBOX/valid-persistent-data/run-customize.sh" >"$VALID_LOG" 2>&1
grep -q '^  code=previews-restored$' "$VALID_LOG"
grep -q '^  copied=1$' "$VALID_LOG"
cmp "$VALID_ORIGINAL/regular.ttf" "$MODPATH/webroot/custom-fonts/$CUSTOM_ID/regular.ttf"
cmp "$VALID_ORIGINAL/bold.ttf" "$MODPATH/webroot/custom-fonts/$CUSTOM_ID/bold.ttf"
[ -f "$VALID_ORIGINAL/name.b64" ]

# Corrupt metadata/font state is skipped without deleting or moving originals.
run_install_case corrupt-persistent-data
make_valid_persistent_font
CORRUPT_ORIGINAL="$CUSTOM_DIR"
printf '%064d\n' 0 >"$CORRUPT_ORIGINAL/regular.sha256"
CORRUPT_LOG="$SANDBOX/corrupt-persistent.log"
sh "$SANDBOX/corrupt-persistent-data/run-customize.sh" >"$CORRUPT_LOG" 2>&1
grep -q '^  status=warning$' "$CORRUPT_LOG"
grep -q '^  code=custom-data-skipped$' "$CORRUPT_LOG"
grep -q "^  skipped_custom=$CUSTOM_ID$" "$CORRUPT_LOG"
[ -f "$CORRUPT_ORIGINAL/regular.ttf" ]
[ -f "$CORRUPT_ORIGINAL/bold.ttf" ]
[ ! -e "$MODPATH/webroot/custom-fonts/$CUSTOM_ID" ]
grep -q "$CUSTOM_ID: invalid, incompatible, or unreadable; original preserved in place" \
  "$TEST_ROOT/data/adb/persian_font_switcher/quarantine/skipped-custom-data.log"

# Legacy data and a stale lock are recoverable and stay untouched.
run_install_case stale-persistent-data
STALE_ROOT="$TEST_ROOT/data/adb/persian_font_switcher"
mkdir -p "$STALE_ROOT/custom-fonts/legacy-font" "$STALE_ROOT/.preview-sync-lock"
printf '%s\n' legacy >"$STALE_ROOT/custom-fonts/legacy-font/README"
STALE_LOG="$SANDBOX/stale-persistent.log"
sh "$SANDBOX/stale-persistent-data/run-customize.sh" >"$STALE_LOG" 2>&1
grep -q '^  code=custom-data-skipped$' "$STALE_LOG"
grep -q '^  recovered_stale_lock=1$' "$STALE_LOG"
[ -f "$STALE_ROOT/custom-fonts/legacy-font/README" ]
[ ! -e "$STALE_ROOT/.preview-sync-lock" ]
find "$STALE_ROOT/quarantine" -maxdepth 1 -type d -name 'stale-preview-sync-lock.*' | grep -q .
[ "$(stat -c '%a' "$MODPATH/scripts/apply-font.sh")" = "755" ]
[ ! -e "$MODPATH/skip_mount" ]

# A permission-restricted registry is non-fatal. On privileged test runners the
# read probe may still succeed; either result must preserve the original file.
run_install_case permission-restricted-data
make_valid_persistent_font
RESTRICTED_ORIGINAL="$CUSTOM_DIR"
chmod 0000 "$RESTRICTED_ORIGINAL/regular.ttf"
RESTRICTED_LOG="$SANDBOX/permission-restricted.log"
sh "$SANDBOX/permission-restricted-data/run-customize.sh" >"$RESTRICTED_LOG" 2>&1
chmod 0600 "$RESTRICTED_ORIGINAL/regular.ttf"
[ -f "$RESTRICTED_ORIGINAL/regular.ttf" ]
grep -Eq '^  code=(custom-root-unreadable|custom-data-skipped|previews-restored)$' "$RESTRICTED_LOG"
[ "$(stat -c '%a' "$MODPATH/scripts/apply-font.sh")" = "755" ]
[ ! -e "$MODPATH/skip_mount" ]

# An inaccessible/legacy custom root (represented safely by a symlink) is
# rejected without traversal, removal, or installation failure.
run_install_case unsafe-persistent-root
UNSAFE_ROOT="$TEST_ROOT/data/adb/persian_font_switcher"
mkdir -p "$UNSAFE_ROOT" "$TEST_ROOT/legacy-font-store"
printf '%s\n' preserve >"$TEST_ROOT/legacy-font-store/marker"
ln -s "$TEST_ROOT/legacy-font-store" "$UNSAFE_ROOT/custom-fonts"
UNSAFE_LOG="$SANDBOX/unsafe-persistent.log"
sh "$SANDBOX/unsafe-persistent-root/run-customize.sh" >"$UNSAFE_LOG" 2>&1
grep -q '^  code=unsafe-custom-root$' "$UNSAFE_LOG"
[ -L "$UNSAFE_ROOT/custom-fonts" ]
[ -f "$TEST_ROOT/legacy-font-store/marker" ]
[ "$(stat -c '%a' "$MODPATH/scripts/apply-font.sh")" = "755" ]
[ ! -e "$MODPATH/skip_mount" ]

# Even an unexpected synchronizer failure is diagnostic-only at installation;
# the trusted initial overlay apply and final permission pass still run.
run_install_case unexpected-sync-failure
printf '%s\n' '#!/system/bin/sh' 'echo status=error' 'echo code=simulated-failure' 'exit 17' \
  >"$MODPATH/scripts/sync-custom.sh"
chmod 0644 "$MODPATH/scripts/sync-custom.sh"
UNEXPECTED_LOG="$SANDBOX/unexpected-sync.log"
sh "$SANDBOX/unexpected-sync-failure/run-customize.sh" >"$UNEXPECTED_LOG" 2>&1
grep -q '^Custom-font preview restore output (exit 17):$' "$UNEXPECTED_LOG"
grep -q '^  code=simulated-failure$' "$UNEXPECTED_LOG"
grep -q '^Warning: preview restoration failed unexpectedly; persistent custom data was left untouched and installation will continue\.$' "$UNEXPECTED_LOG"
grep -q '^Initial font apply output (exit 0):$' "$UNEXPECTED_LOG"
[ "$(stat -c '%a' "$MODPATH/scripts/sync-custom.sh")" = "755" ]
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
