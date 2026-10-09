#!/bin/sh
# Synthetic development archive; fail closed and never overwrite another WAL file.
set -eu
[ ! -f /archive/TEST_ONLY_PAUSE ] || exit 1
case "$2" in *[!0-9A-Fa-f.backuphistory]*) exit 1;; esac
destination="/archive/wal/$2"
if [ -e "$destination" ]; then cmp -s "$1" "$destination"; exit $?; fi
temporary="/archive/wal/.$2.$$"
trap 'rm -f "$temporary"' EXIT
cp "$1" "$temporary"
sync "$temporary"
ln "$temporary" "$destination" || cmp -s "$temporary" "$destination"
