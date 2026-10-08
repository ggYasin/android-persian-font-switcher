#!/system/bin/sh
# Removes the staged font copies and patched XML. Persistent custom-font
# originals under /data/adb/persian_font_switcher are intentionally retained.
FONT_ROOT=/data/fonts/persian_font_switcher
if [ -d "$FONT_ROOT" ] && [ ! -L "$FONT_ROOT" ]; then
  rm -rf "$FONT_ROOT"
fi
