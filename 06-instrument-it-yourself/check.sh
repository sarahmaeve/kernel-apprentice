#!/usr/bin/env bash
# Lesson 06 check — "Instrument it yourself" (CHALLENGE).
#
# Builds your counter.ko, boots a guest that loads it, triggers getpid 50 times,
# and reads /proc/kernel-apprentice-count. Grades:
#   PASS iff /proc reports a NON-ZERO getpid count (i.e. you implemented both TODOs).
# Red until then — the shipped skeleton counts nothing.

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

log "building counter.ko against $KERNEL_SRC"
make -C "$HERE/module" KDIR="$KERNEL_SRC" >/dev/null
ko="$HERE/module/counter.ko"
[ -f "$ko" ] || die "module build produced no counter.ko"

work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
gcc -static -O2 -o "$work/trigger" "$HERE/trigger.c"
overlay="$work/overlay"; mkdir -p "$overlay"
cp "$ko" "$overlay/counter.ko"
cp "$work/trigger" "$overlay/trigger"
cat > "$overlay/init" <<'INIT'
#!/bin/busybox sh
busybox mount -t proc     none /proc
busybox mount -t sysfs    none /sys
busybox mount -t devtmpfs none /dev 2>/dev/null
echo "=== insmod counter.ko (registers a kprobe on getpid) ==="
insmod /counter.ko
/trigger                       # call getpid 50 times
echo "=== cat /proc/kernel-apprentice-count ==="
cat /proc/kernel-apprentice-count
echo "(end)"
rmmod counter
echo "APPRENTICE-DONE"
busybox poweroff -f
INIT
chmod +x "$overlay/init"

img="$work/initramfs.cpio.gz"
mk_initramfs "$img" "$overlay"

logf="$work/serial.log"
"$ROOT/harness/run-qemu.sh" "$img" --timeout 90 --log "$logf"

if grep -Eq "getpid calls: [1-9][0-9]*" "$logf"; then
  ok "your counter reported a non-zero getpid count via /proc"
  ok "lesson 06 complete — you instrumented the kernel yourself"
else
  die "no non-zero \"getpid calls: N\" line at /proc/kernel-apprentice-count.
     Implement the two TODOs in module/counter.c (count in ka_pre_handler,
     print in ka_show) — see README.md. (got: $(grep -a 'getpid calls' "$logf" || echo 'no output'))"
fi
