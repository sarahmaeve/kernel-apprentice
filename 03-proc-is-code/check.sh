#!/usr/bin/env bash
# Lesson 03 check — "/proc is code, not files".
#
# Builds proc_window.ko, boots a guest that insmods it, reads the new /proc entry
# (twice, to show it's regenerated each read), then rmmods it. Grades:
#   PASS iff the serial log shows BOTH
#     * kernel-apprentice: hello from a seq_file handler   (the entry produced output)
#     * kernel-apprentice: /proc/kernel-apprentice created  (the module created it)

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

log "building proc_window.ko against $KERNEL_SRC"
make -C "$HERE/module" KDIR="$KERNEL_SRC" >/dev/null
ko="$HERE/module/proc_window.ko"
[ -f "$ko" ] || die "module build produced no proc_window.ko"

work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
overlay="$work/overlay"; mkdir -p "$overlay"
cp "$ko" "$overlay/proc_window.ko"
cat > "$overlay/init" <<'INIT'
#!/bin/busybox sh
busybox mount -t proc     none /proc
busybox mount -t sysfs    none /sys
busybox mount -t devtmpfs none /dev 2>/dev/null
echo "=== insmod (ka_init runs proc_create) ==="
insmod /proc_window.ko
echo "=== cat /proc/kernel-apprentice (generated on read) ==="
cat /proc/kernel-apprentice
echo "=== read it again — live values change, because it's code, not a file ==="
cat /proc/kernel-apprentice
echo "=== dmesg ==="
dmesg | grep "kernel-apprentice: /proc"
echo "=== rmmod (ka_exit runs proc_remove) ==="
rmmod proc_window
dmesg | grep "kernel-apprentice: /proc/kernel-apprentice removed"
echo "APPRENTICE-DONE"
busybox poweroff -f
INIT
chmod +x "$overlay/init"

img="$work/initramfs.cpio.gz"
mk_initramfs "$img" "$overlay"

logf="$work/serial.log"
"$ROOT/harness/run-qemu.sh" "$img" --timeout 90 --log "$logf"

grep -q "kernel-apprentice: hello from a seq_file handler" "$logf" \
  || die "no seq_file output — did /proc/kernel-apprentice get created + read? (see $logf)"
ok "the /proc entry produced output from your seq_file handler"
grep -q "kernel-apprentice: /proc/kernel-apprentice created" "$logf" \
  || die "no creation log line — did the module load? (see $logf)"
ok "the module created /proc/kernel-apprentice"
ok "lesson 03 complete"
