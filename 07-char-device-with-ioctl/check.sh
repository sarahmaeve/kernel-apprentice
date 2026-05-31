#!/usr/bin/env bash
# Lesson 07 check — a character device with an ioctl (CHALLENGE, build it).
#
# Builds ka_chardev.ko + the userspace acceptance test, boots a guest that loads the
# module and runs the test against /dev/ka-chardev. Grades:
#   PASS iff the test prints "TEST PASS" — i.e. read/write/ioctl are all implemented.
# Red until then: the shipped stubs reject writes and answer no ioctls.

set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$HERE"; while [ ! -d "$ROOT/harness" ] && [ "$ROOT" != / ]; do ROOT="$(dirname "$ROOT")"; done
# shellcheck source=../harness/lib.sh
source "$ROOT/harness/lib.sh"
# shellcheck source=../harness/initramfs.sh
source "$ROOT/harness/initramfs.sh"
assert_in_container
need make; need gcc

ensure_kernel

log "building ka_chardev.ko against $KERNEL_SRC"
make -C "$HERE/module" KDIR="$KERNEL_SRC" >/dev/null
ko="$HERE/module/ka_chardev.ko"
[ -f "$ko" ] || die "module build produced no ka_chardev.ko"

work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
gcc -static -O2 -o "$work/test" "$HERE/test.c"
overlay="$work/overlay"; mkdir -p "$overlay"
cp "$ko" "$overlay/ka_chardev.ko"
cp "$work/test" "$overlay/test"
cat > "$overlay/init" <<'INIT'
#!/bin/busybox sh
busybox mount -t proc     none /proc
busybox mount -t sysfs    none /sys
busybox mount -t devtmpfs none /dev 2>/dev/null
echo "=== insmod ka_chardev.ko ==="
insmod /ka_chardev.ko
busybox ls -l /dev/ka-chardev 2>&1 || echo "(no /dev node)"
echo "=== running the userspace test ==="
/test
echo "test exit: $?"
echo "APPRENTICE-DONE"
busybox poweroff -f
INIT
chmod +x "$overlay/init"

img="$work/initramfs.cpio.gz"
mk_initramfs "$img" "$overlay"

logf="$work/serial.log"
"$ROOT/harness/run-qemu.sh" "$img" --timeout 90 --log "$logf"

if grep -q "TEST PASS" "$logf"; then
  ok "the userspace test passed — your char device's read/write/ioctl all work"
  ok "lesson 07 complete"
else
  die "the test did not pass. Implement the three handlers in module/ka_chardev.c
     (ka_write stores, ka_read returns it, ka_ioctl answers KA_GET_LEN) — see the
     FAIL line above and README.md hints. (log: $logf)"
fi
