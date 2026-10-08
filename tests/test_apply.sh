#!/usr/bin/env sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
SANDBOX=$(mktemp -d)
trap 'rm -rf -- "$SANDBOX"' EXIT HUP INT TERM

. "$SCRIPT_DIR/redirect_fixture.sh"
pfs_fixture_init "$SANDBOX"

apply() {
  pfs_fixture_env PFS_SKIP_KSU_CONFIG=1 sh "$MODULE/scripts/apply-font.sh" "$1"
}

status() {
  pfs_fixture_env sh "$MODULE/scripts/get-status.sh"
}

assert_generation() {
  FONT_ID="$1"
  GEN="$2"
  for TARGET in NotoNaskhArabicUI-Regular.ttf NotoNaskhArabic-Regular.ttf; do
    cmp "$MODULE/assets/fonts/$FONT_ID/regular.ttf" "$FONT_ROOT/gen/$GEN/$TARGET"
  done
  for TARGET in NotoNaskhArabicUI-Bold.ttf NotoNaskhArabic-Bold.ttf; do
    cmp "$MODULE/assets/fonts/$FONT_ID/bold.ttf" "$FONT_ROOT/gen/$GEN/$TARGET"
  done
  [ "$(sed -n '1p' "$FONT_ROOT/generation")" = "$GEN" ]
  for XML in font_fallback.xml fonts.xml; do
    for TARGET in NotoNaskhArabicUI-Regular.ttf NotoNaskhArabicUI-Bold.ttf \
      NotoNaskhArabic-Regular.ttf NotoNaskhArabic-Bold.ttf; do
      grep -q "\.\./\.\.$FONT_ROOT/gen/$GEN/$TARGET" "$FONT_ROOT/xml/$GEN/$XML"
    done
    grep -q 'postScriptName="NotoNaskhArabic"' "$FONT_ROOT/xml/$GEN/$XML"
    grep -q 'postScriptName="NotoNaskhArabicUI"' "$FONT_ROOT/xml/$GEN/$XML"
  done
  [ ! -e "$MODULE/system" ]
  [ ! -e "$MODULE/skip_mount" ]
}

# Every bundled family stages four exact copies into a fresh generation and a
# patched copy of both ROM font XML files.
EXPECTED_GEN=0
for FONT_ID in $(sed -n 's/.*"id": "\([a-z0-9_-]*\)".*/\1/p' "$PROJECT_DIR/webroot/font-manifest.json"); do
  [ "$FONT_ID" = system-default ] && continue
  EXPECTED_GEN=$((EXPECTED_GEN + 1))
  RESULT=$(apply "$FONT_ID")
  printf '%s\n' "$RESULT" | grep -q '^status=ok$'
  printf '%s\n' "$RESULT" | grep -q "^generation=$EXPECTED_GEN$"
  assert_generation "$FONT_ID" "$EXPECTED_GEN"
done

# Re-applying the staged font reuses its generation instead of copying again.
LAST_FONT=ibm-plex-sans-arabic
apply "$LAST_FONT" | grep -q "^generation=$EXPECTED_GEN$"
assert_generation "$LAST_FONT" "$EXPECTED_GEN"

# A previous generation is never rewritten while a new one is staged.
VAZIR_GEN=$((EXPECTED_GEN + 1))
apply vazirmatn >/dev/null
assert_generation vazirmatn "$VAZIR_GEN"
cmp "$MODULE/assets/fonts/$LAST_FONT/regular.ttf" "$FONT_ROOT/gen/$EXPECTED_GEN/NotoNaskhArabicUI-Regular.ttf"
# Its XML is immutable too: it still points only at its own generation.
[ "$(grep -c "gen/$EXPECTED_GEN/NotoNaskhArabic" "$FONT_ROOT/xml/$EXPECTED_GEN/font_fallback.xml")" -eq 4 ]
if grep -q "gen/$VAZIR_GEN/" "$FONT_ROOT/xml/$EXPECTED_GEN/font_fallback.xml"; then
  echo "A published XML generation was rewritten" >&2
  exit 1
fi

# Status: active comes from the verified redirect of the running system_server.
pfs_fixture_system_server 400
pfs_fixture_bind 400 font_fallback.xml "$VAZIR_GEN"
pfs_fixture_bind 400 fonts.xml "$VAZIR_GEN"
pfs_fixture_state state=verified mode=boot ss_pid=400 "generation=$VAZIR_GEN" font=vazirmatn
STATUS=$(status)
printf '%s\n' "$STATUS" | grep -q '^active=vazirmatn$'
printf '%s\n' "$STATUS" | grep -q '^selected=vazirmatn$'
printf '%s\n' "$STATUS" | grep -q '^restart_required=false$'
printf '%s\n' "$STATUS" | grep -q '^active_scope=font-service$'
printf '%s\n' "$STATUS" | grep -q '^redirect=verified$'
printf '%s\n' "$STATUS" | grep -q "^generation=$VAZIR_GEN$"
printf '%s\n' "$STATUS" | grep -q '^boot_guard=ok$'
printf '%s\n' "$STATUS" | grep -q '^fontloader=not-detected$'

apply estedad >/dev/null
STATUS=$(status)
printf '%s\n' "$STATUS" | grep -q '^active=vazirmatn$'
printf '%s\n' "$STATUS" | grep -q '^selected=estedad$'
printf '%s\n' "$STATUS" | grep -q '^restart_required=true$'

# A bind that predates nothing (font service already published) is unverified.
pfs_fixture_state state=bound ss_pid=400 "generation=$VAZIR_GEN" font=vazirmatn font_service_at_bind=present
status | grep -q '^active=unknown$'
# A record from a previous system_server is stale.
pfs_fixture_state state=verified ss_pid=399 "generation=$VAZIR_GEN" font=vazirmatn
status | grep -q '^active=unknown$'
# No bind and an inactive record means stock fonts are served.
pfs_fixture_unbind 400 font_fallback.xml
pfs_fixture_unbind 400 fonts.xml
pfs_fixture_state state=inactive reason=system-default
status | grep -q '^active=system-default$'
rm -f "$MODULE/runtime/redirect.state"
STATUS=$(status)
printf '%s\n' "$STATUS" | grep -q '^active=unknown$'
printf '%s\n' "$STATUS" | grep -q '^redirect=none$'

mkdir -p "$ADB/modules/fontloader"
printf '%s\n' 'id=fontloader' >"$ADB/modules/fontloader/module.prop"
status | grep -q '^fontloader=enabled$'
: >"$ADB/modules/fontloader/disable"
status | grep -q '^fontloader=disabled$'
rm -f "$ADB/modules/fontloader/disable"
: >"$ADB/modules/fontloader/remove"
status | grep -q '^fontloader=pending-removal$'
rm -rf "$ADB/modules/fontloader"
mkdir -p "$ADB/modules_update/fontloader"
printf '%s\n' 'id=fontloader' >"$ADB/modules_update/fontloader/module.prop"
status | grep -q '^fontloader=pending-install$'
mkdir -p "$ADB/modules/fontloader"
printf '%s\n' 'id=fontloader' >"$ADB/modules/fontloader/module.prop"
status | grep -q '^fontloader=pending-install-or-update$'
rm -rf "$ADB/modules/fontloader" "$ADB/modules_update/fontloader"

# A stale KernelSU config must not override the module state file.
mkdir -p "$ADB/ksu/bin"
printf '%s\n' '#!/usr/bin/env sh' 'printf "%s\n" vazirmatn' >"$ADB/ksu/bin/ksud"
chmod 0755 "$ADB/ksu/bin/ksud"
STATE_SELECTION=$(pfs_fixture_env sh -c '. "$1"; pfs_read_selection' sh "$MODULE/scripts/lib.sh")
[ "$STATE_SELECTION" = estedad ]
rm -rf "$ADB/ksu"

# Unsafe IDs are rejected before anything is staged.
BEFORE=$(find "$FONT_ROOT" -type f -exec sha256sum {} + | sort)
if apply '../../escape' >/dev/null 2>&1; then
  echo "Path traversal ID was accepted" >&2
  exit 1
fi
if apply 'sahel;touch-pwned' >/dev/null 2>&1; then
  echo "Shell metacharacter ID was accepted" >&2
  exit 1
fi
[ "$BEFORE" = "$(find "$FONT_ROOT" -type f -exec sha256sum {} + | sort)" ]

# A live kernel-held flock blocks a second operation and is released
# automatically even if the holder is killed.
LOCK_READY="$SANDBOX/lock-ready"
LOCK_GATE="$SANDBOX/lock-gate"
mkfifo "$LOCK_GATE"
(
  exec 8>>"$MODULE/.apply-lock"
  flock 8
  : >"$LOCK_READY"
  IFS= read -r _ <"$LOCK_GATE" || true
) &
LOCK_HOLDER=$!
while [ ! -e "$LOCK_READY" ]; do sleep 0.05; done
if apply vazirmatn >/dev/null 2>&1; then
  echo "Concurrent apply lock was ignored" >&2
  exit 1
fi
printf '%s\n' release >"$LOCK_GATE"
wait "$LOCK_HOLDER"
rm -f "$LOCK_READY" "$LOCK_GATE"

CRASH_LOCK_READY="$SANDBOX/crash-lock-ready"
CRASH_LOCK_GATE="$SANDBOX/crash-lock-gate"
mkfifo "$CRASH_LOCK_GATE"
(
  exec 8>>"$MODULE/.apply-lock"
  flock 8
  : >"$CRASH_LOCK_READY"
  IFS= read -r _ <"$CRASH_LOCK_GATE" || true
) &
CRASH_LOCK_HOLDER=$!
while [ ! -e "$CRASH_LOCK_READY" ]; do sleep 0.05; done
kill -KILL "$CRASH_LOCK_HOLDER"
wait "$CRASH_LOCK_HOLDER" 2>/dev/null || true
apply vazirmatn | grep -q '^status=ok$'
rm -f "$CRASH_LOCK_READY" "$CRASH_LOCK_GATE"

# A non-regular lock path is an explicit capability error and is never followed.
rm -f "$MODULE/.apply-lock"
printf '%s\n' preserve >"$SANDBOX/external-lock-target"
ln -s "$SANDBOX/external-lock-target" "$MODULE/.apply-lock"
UNSAFE_LOCK_RESULT=$(apply vazirmatn 2>&1 || true)
printf '%s\n' "$UNSAFE_LOCK_RESULT" | grep -q '^code=lock-unavailable$'
[ "$(sed -n '1p' "$SANDBOX/external-lock-target")" = preserve ]
rm -f "$MODULE/.apply-lock"

# An owner-identified dead directory lock from an older release is migrated.
mkdir "$MODULE/.apply-lock"
printf '%s\n' 99999999 >"$MODULE/.apply-lock/pid"
STALE_RESULT=$(apply vazirmatn)
printf '%s\n' "$STALE_RESULT" | grep -q '^status=ok$'
printf '%s\n' "$STALE_RESULT" | grep -q '^recovered_stale_lock=1$'
[ -f "$MODULE/.apply-lock" ]

# A state-write failure reports a distinct error and keeps the old selection.
apply estedad >/dev/null
rm "$MODULE/state/selected-font"
mkdir "$MODULE/state/selected-font"
STATE_FAILURE=$(apply vazirmatn 2>&1 || true)
printf '%s\n' "$STATE_FAILURE" | grep -q '^code=state-write-failed$'
rmdir "$MODULE/state/selected-font"
printf '%s\n' estedad >"$MODULE/state/selected-font"

# A corrupt bundled asset is rejected and stages nothing.
GEN_BEFORE=$(sed -n '1p' "$FONT_ROOT/generation")
cp "$MODULE/assets/fonts/sahel/regular.ttf" "$SANDBOX/sahel-regular.bak"
printf '%s' broken >"$MODULE/assets/fonts/sahel/regular.ttf"
CORRUPT=$(apply sahel 2>&1 || true)
printf '%s\n' "$CORRUPT" | grep -q '^code=font-checksum-mismatch$'
[ "$(sed -n '1p' "$FONT_ROOT/generation")" = "$GEN_BEFORE" ]
[ "$(sed -n '1p' "$MODULE/state/selected-font")" = estedad ]
cp "$SANDBOX/sahel-regular.bak" "$MODULE/assets/fonts/sahel/regular.ttf"

# A ROM XML that lacks a target, or was already redirected, fails closed
# without changing the selection.
cp "$SYSTEM/etc/font_fallback.xml" "$SANDBOX/font_fallback.xml.bak"
sed -i 's/NotoNaskhArabic-Bold\.ttf/SomethingElse-Bold.ttf/' "$SYSTEM/etc/font_fallback.xml"
GEN_BEFORE=$(sed -n '1p' "$FONT_ROOT/generation")
MISSING=$(apply shabnam 2>&1 || true)
printf '%s\n' "$MISSING" | grep -q '^code=redirect-prepare-failed$'
[ "$(sed -n '1p' "$MODULE/state/selected-font")" = estedad ]
# Nothing half-built is published.
[ "$(sed -n '1p' "$FONT_ROOT/generation")" = "$GEN_BEFORE" ]
[ ! -e "$FONT_ROOT/gen/$((GEN_BEFORE + 1))" ]
[ ! -e "$FONT_ROOT/xml/$((GEN_BEFORE + 1))" ]
cp "$FONT_ROOT/xml/$GEN_BEFORE/font_fallback.xml" "$SYSTEM/etc/font_fallback.xml"
REPATCH=$(apply shabnam 2>&1 || true)
printf '%s\n' "$REPATCH" | grep -q '^code=redirect-prepare-failed$'
cp "$SANDBOX/font_fallback.xml.bak" "$SYSTEM/etc/font_fallback.xml"

# Applying a font re-arms activation after a tripped boot guard.
printf '%s\n' 2 >"$MODULE/state/boot-guard"
status | grep -q '^boot_guard=tripped$'
apply shabnam | grep -q '^status=ok$'
[ ! -e "$MODULE/state/boot-guard" ]
status | grep -q '^boot_guard=ok$'

# System Default records the choice without staging anything new.
GEN_BEFORE=$(sed -n '1p' "$FONT_ROOT/generation")
SYSTEM_DEFAULT=$(apply system-default)
printf '%s\n' "$SYSTEM_DEFAULT" | grep -q '^status=ok$'
printf '%s\n' "$SYSTEM_DEFAULT" | grep -q '^generation=none$'
[ "$(sed -n '1p' "$MODULE/state/selected-font")" = system-default ]
[ "$(sed -n '1p' "$FONT_ROOT/generation")" = "$GEN_BEFORE" ]
pfs_fixture_state state=inactive reason=system-default
STATUS=$(status)
printf '%s\n' "$STATUS" | grep -q '^active=system-default$'
printf '%s\n' "$STATUS" | grep -q '^restart_required=false$'

# Installation mode only records a verified selection.
RECORD_ONLY=$(pfs_fixture_env PFS_SKIP_KSU_CONFIG=1 PFS_SKIP_REDIRECT_STAGE=1 \
  sh "$MODULE/scripts/apply-font.sh" gandom)
printf '%s\n' "$RECORD_ONLY" | grep -q '^generation=none$'
[ "$(sed -n '1p' "$FONT_ROOT/generation")" = "$GEN_BEFORE" ]
[ "$(sed -n '1p' "$MODULE/state/selected-font")" = gandom ]

printf '%s\n' invalid-target.ttf >"$MODULE/state/supported-targets"
if apply vazirmatn >/dev/null 2>&1; then
  echo "Invalid target allowlist was accepted" >&2
  exit 1
fi
cp "$PROJECT_DIR/state/supported-targets" "$MODULE/state/supported-targets"
status | grep -q '^layout=valid$'

echo "Apply-script tests passed"
