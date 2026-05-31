#!/usr/bin/env bash
# Lesson 02 check — "printk and the ring buffer".
#
# Builds hello.ko against the pinned kernel tree, boots a guest that insmods it,
# dumps the ring buffer, and rmmods it. Grades:
#   PASS iff the serial log shows BOTH
#     * kernel-apprentice: hello at INFO   (module loaded, emitted to the buffer)
#     * kernel-apprentice: goodbye         (module unloaded cleanly, __exit ran)

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

log "building hello.ko against $KERNEL_SRC"
make -C "$HERE/module" KDIR="$KERNEL_SRC" >/dev/null
ko="$HERE/module/hello.ko"
[ -f "$ko" ] || die "module build produced no hello.ko"

work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
overlay="$work/overlay"; mkdir -p "$overlay"
cp "$ko" "$overlay/hello.ko"
cat > "$overlay/init" <<'INIT'
#!/bin/busybox sh
busybox mount -t proc     none /proc
busybox mount -t sysfs    none /sys
busybox mount -t devtmpfs none /dev 2>/dev/null
echo "=== insmod (hello_init runs) ==="
insmod /hello.ko
echo "=== dmesg: the ring buffer holds every level ==="
dmesg | grep kernel-apprentice
echo "=== rmmod (hello_exit runs) ==="
rmmod hello
dmesg | grep "kernel-apprentice: goodbye"
echo "APPRENTICE-DONE"
busybox poweroff -f
INIT
chmod +x "$overlay/init"

img="$work/initramfs.cpio.gz"
mk_initramfs "$img" "$overlay"

logf="$work/serial.log"
"$ROOT/harness/run-qemu.sh" "$img" --timeout 90 --log "$logf"

grep -q "kernel-apprentice: hello at INFO" "$logf" \
  || die "module did not emit its INFO line — did it load? (see $logf)"
ok "module loaded and wrote to the ring buffer"
grep -q "kernel-apprentice: goodbye" "$logf" \
  || die "no 'goodbye' — module did not unload cleanly (see $logf)"
ok "module unloaded cleanly (__exit ran)"
ok "lesson 02 complete"
