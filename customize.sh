#!/system/bin/sh

DEVICE_API="${API:-$(getprop ro.build.version.sdk 2>/dev/null)}"

if [ "$DEVICE_API" != "36" ]; then
  abort "This module is built for Android 16 / API 36; detected API: ${DEVICE_API:-unknown}."
fi

for FONT_PATH in \
  /system/fonts/NotoNaskhArabicUI-Regular.ttf \
  /system/fonts/NotoNaskhArabicUI-Bold.ttf \
  /system/fonts/NotoNaskhArabic-Regular.ttf \
  /system/fonts/NotoNaskhArabic-Bold.ttf
do
  if [ ! -f "$FONT_PATH" ]; then
    abort "Expected ROM font is absent: $FONT_PATH"
  fi
done

for FONT_NAME in \
  NotoNaskhArabicUI-Regular.ttf \
  NotoNaskhArabicUI-Bold.ttf \
  NotoNaskhArabic-Regular.ttf \
  NotoNaskhArabic-Bold.ttf
do
  MODULE_FONT="$MODPATH/system/fonts/$FONT_NAME"
  if [ ! -f "$MODULE_FONT" ]; then
    abort "Module font is absent: $FONT_NAME"
  fi
  set_perm "$MODULE_FONT" 0 0 0644
done

ui_print "Vazirmatn UI Non-Latin Arabic fallbacks validated for API 36."
