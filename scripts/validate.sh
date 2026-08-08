#!/usr/bin/env sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
ARCHIVE=${1:-"$PROJECT_DIR/Vazirmatn-Persian-Fallback-v33.003.zip"}
EXTRACTED=$(mktemp -d)
EXPECTED=$(mktemp)
ACTUAL=$(mktemp)
trap 'rm -rf -- "$EXTRACTED" "$EXPECTED" "$ACTUAL"' EXIT HUP INT TERM

cat >"$EXPECTED" <<'EOF'
customize.sh
module.prop
system/fonts/NotoNaskhArabic-Bold.ttf
system/fonts/NotoNaskhArabic-Regular.ttf
system/fonts/NotoNaskhArabicUI-Bold.ttf
system/fonts/NotoNaskhArabicUI-Regular.ttf
EOF

unzip -Z1 "$ARCHIVE" | sed '/\/$/d' | LC_ALL=C sort >"$ACTUAL"
diff -u "$EXPECTED" "$ACTUAL"
unzip -q "$ARCHIVE" -d "$EXTRACTED"

cmp "$PROJECT_DIR/module.prop" "$EXTRACTED/module.prop"
cmp "$PROJECT_DIR/customize.sh" "$EXTRACTED/customize.sh"
for name in \
  NotoNaskhArabicUI-Regular.ttf \
  NotoNaskhArabicUI-Bold.ttf \
  NotoNaskhArabic-Regular.ttf \
  NotoNaskhArabic-Bold.ttf
do
  file "$EXTRACTED/system/fonts/$name" | grep -q 'TrueType Font data'
  cmp "$PROJECT_DIR/system/fonts/$name" "$EXTRACTED/system/fonts/$name"
done

test "$(sha256sum "$EXTRACTED/system/fonts/NotoNaskhArabicUI-Regular.ttf" | cut -d' ' -f1)" = "99e8e85dc30507c90562c2967f1f2c29b64d45763d3807abe30fadf451bd64fc"
test "$(sha256sum "$EXTRACTED/system/fonts/NotoNaskhArabic-Regular.ttf" | cut -d' ' -f1)" = "99e8e85dc30507c90562c2967f1f2c29b64d45763d3807abe30fadf451bd64fc"
test "$(sha256sum "$EXTRACTED/system/fonts/NotoNaskhArabicUI-Bold.ttf" | cut -d' ' -f1)" = "f93fe4bcf136cd1131a475813e0916657055ba745f66d28cff091016bb2e4454"
test "$(sha256sum "$EXTRACTED/system/fonts/NotoNaskhArabic-Bold.ttf" | cut -d' ' -f1)" = "f93fe4bcf136cd1131a475813e0916657055ba745f66d28cff091016bb2e4454"

if unzip -Z1 "$ARCHIVE" | grep -Eq '(^|/)(\.git|__MACOSX)(/|$)|(^|/)\.DS_Store$|(~|\.swp|\.tmp)$'; then
  echo "Unexpected metadata or temporary file in archive" >&2
  exit 1
fi

echo "Validated: $ARCHIVE"
sha256sum "$ARCHIVE"
