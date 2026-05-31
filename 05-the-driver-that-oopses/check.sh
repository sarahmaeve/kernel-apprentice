#!/usr/bin/env bash
# Lesson 05 check — "The driver that oopses" (CHALLENGE, read + fix).
#
# Builds oops_driver.ko, boots a guest that loads it and writes to /proc/ka-oops
# (in a child process, so the oops kills the writer, not init). Grades:
#   RED  while the bug is present -> a NULL-deref oops appears in the log
#   PASS when fixed -> the write completes ("ka-oops stored N bytes") and NO oops.

set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$HERE"; while [ ! -d "$ROOT/harness" ] && [ "$ROOT" != / ]; do ROOT="$(dirname "$ROOT")"; done
# shellcheck source=../harness/lib.sh
source "$ROOT/harness/lib.sh"
# shellcheck source=../harness/initramfs.sh
source "$ROOT/harness/initramfs.sh"
assert_in_container
need make

ensure_kernel

log "building oops_driver.ko against $KERNEL_SRC"
make -C "$HERE/module" KDIR="$KERNEL_SRC" >/dev/null
ko="$HERE/module/oops_driver.ko"
[ -f "$ko" ] || die "module build produced no oops_driver.ko"

work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
overlay="$work/overlay"; mkdir -p "$overlay"
cp "$ko" "$overlay/oops_driver.ko"
cat > "$overlay/init" <<'INIT'
#!/bin/busybox sh
busybox mount -t proc     none /proc
busybox mount -t sysfs    none /sys
busybox mount -t devtmpfs none /dev 2>/dev/null
echo "=== insmod oops_driver.ko ==="
insmod /oops_driver.ko
echo "=== write to /proc/ka-oops (in a child — oopses while the bug is present) ==="
busybox sh -c 'echo hello-from-userspace > /proc/ka-oops' 2>&1
echo "(writer process returned $?)"
echo "=== dmesg (the oops trace, or the success line if you fixed it) ==="
dmesg | busybox tail -n 40
echo "APPRENTICE-DONE"
busybox poweroff -f
INIT
chmod +x "$overlay/init"

img="$work/initramfs.cpio.gz"
mk_initramfs "$img" "$overlay"

logf="$work/serial.log"
"$ROOT/harness/run-qemu.sh" "$img" --timeout 90 --log "$logf"

if grep -qiE "kernel NULL pointer dereference|BUG: unable to handle|general protection fault|Oops:" "$logf"; then
  die "the driver OOPSED on write.
     Read the trace above: the RIP / Call Trace points at ka_write in
     module/oops_driver.c. Which pointer does it write through, and where should it
     have been allocated? Fix it so the write succeeds. See README.md hints."
elif grep -q "kernel-apprentice: ka-oops stored" "$logf"; then
  ok "no oops — the write completed and stored the data; you found and fixed the NULL deref"
  ok "lesson 05 complete"
else
  die "no oops, but nothing was stored either — does ka_write have a real buffer to
     write into? (see $logf)"
fi
