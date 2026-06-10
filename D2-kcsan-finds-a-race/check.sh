#!/usr/bin/env bash
# Lesson D2 check — "KCSAN finds a race" (CHALLENGE, read + fix).
#
# REQUIRES THE DEBUG OVERLAY KERNEL (lockdep + KCSAN): make debug-kernel, one-time.
# Builds d2_race.ko against the debug tree (so its accesses are instrumented) and
# boots the debug kernel; two workers hammer a shared counter. Grades:
#   RED  while the race is present -> "BUG: KCSAN: data-race" appears (and the
#        count usually comes up short)
#   PASS when fixed -> NO KCSAN report AND the count is EXACT (so silencing the
#        sanitizer without fixing the lost updates can't pass).

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
[ -f "$DEBUG_BZIMAGE" ] || die "Module D's D1/D2 run on the lockdep+KCSAN DEBUG kernel, which isn't built.
     Run 'make debug-kernel' once (a second kernel build — minutes, like C2's KASAN
     kernel), then re-run this check."

log "building d2_race.ko against the debug tree ($DEBUG_SRC)"
make -C "$HERE/module" KDIR="$DEBUG_SRC" >/dev/null
ko="$HERE/module/d2_race.ko"
[ -f "$ko" ] || die "module build produced no d2_race.ko"

work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
overlay="$work/overlay"; mkdir -p "$overlay"
cp "$ko" "$overlay/d2_race.ko"
cat > "$overlay/init" <<'INIT'
#!/bin/busybox sh
busybox mount -t proc     none /proc
busybox mount -t sysfs    none /sys
busybox mount -t devtmpfs none /dev 2>/dev/null
echo "=== insmod d2_race.ko (two workers, one counter; KCSAN is sampling) ==="
insmod /d2_race.ko
echo "===== KCSAN's verdict (only if the race is still present) ====="
dmesg | busybox grep -B2 -A30 "BUG: KCSAN" || echo "(no KCSAN report)"
echo "===== the count ====="
dmesg | busybox grep "d2_race counted"
echo "APPRENTICE-DONE"
busybox poweroff -f
INIT
chmod +x "$overlay/init"

img="$work/initramfs.cpio.gz"
mk_initramfs "$img" "$overlay"

logf="$work/serial.log"
KERNEL_IMAGE="$DEBUG_BZIMAGE" "$ROOT/harness/run-qemu.sh" "$img" --timeout 180 --log "$logf"

grep -q "APPRENTICE-DONE" "$logf" \
  || die "guest never finished — did the debug kernel boot? (see $logf)"

if grep -q "BUG: KCSAN: data-race" "$logf"; then
  die "KCSAN caught the data race (read its two stacks above — same address, two
     CPUs, no ordering). Plain '++' on a shared counter is a read-modify-write that
     two CPUs can interleave: both read N, both store N+1, one event vanishes.
     Fix module/d2_race.c so the counting is race-free. README has hints."
elif grep -q "kernel-apprentice: d2_race counted 400000 of 400000 events" "$logf"; then
  ok "no KCSAN report and the count is exact (400000/400000) — the counting is atomic"
  ok "lesson D2 complete — you read a data race and made it impossible"
else
  grep -o "kernel-apprentice: d2_race counted.*" "$logf" >&2 || true
  die "KCSAN is silent but the count is NOT exact — silencing isn't fixing.
     The check requires both: no data-race report AND 400000 of 400000. (see $logf)"
fi
