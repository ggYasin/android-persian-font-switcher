#!/system/bin/sh
MODDIR=${0%/*}
PFS_MODULE_DIR="$MODDIR" sh "$MODDIR/scripts/boot-tasks.sh" post-fs-data
