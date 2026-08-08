#!/system/bin/sh
set -eu

sync
if [ -x /system/bin/svc ]; then
  if /system/bin/svc power reboot; then
    exit 0
  fi
fi
if [ -x /system/bin/reboot ]; then
  /system/bin/reboot
  exit $?
fi
exit 1
