#!/usr/bin/env bash
# Lesson D1 check — "lockdep on a deadlock" (CHALLENGE, read + fix).
#
# REQUIRES THE DEBUG OVERLAY KERNEL (lockdep + KCSAN): make debug-kernel, one-time.
# Builds d1_locks.ko against the debug tree and boots the debug kernel. The module
# runs two lock-taking routines back-to-back — nothing hangs — yet lockdep proves
# the ordering cycle from one clean run of each path. Grades:
#   RED  while the lock-order bug is present -> "possible circular locking
#        dependency" appears in the log
#   PASS when fixed -> both routines complete and NO lockdep splat.

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

log "building d1_locks.ko against the debug tree ($DEBUG_SRC)"
make -C "$HERE/module" KDIR="$DEBUG_SRC" >/dev/null
ko="$HERE/module/d1_locks.ko"
[ -f "$ko" ] || die "module build produced no d1_locks.ko"

work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
overlay="$work/overlay"; mkdir -p "$overlay"
cp "$ko" "$overlay/d1_locks.ko"
cat > "$overlay/init" <<'INIT'
#!/bin/busybox sh
busybox mount -t proc     none /proc
busybox mount -t sysfs    none /sys
busybox mount -t devtmpfs none /dev 2>/dev/null
echo "=== insmod d1_locks.ko (lockdep is watching every acquisition order) ==="
insmod /d1_locks.ko
echo "===== lockdep's verdict (only if the ordering bug is still present) ====="
dmesg | busybox grep -B5 -A45 "circular locking" || echo "(no lockdep report)"
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

if grep -q "possible circular locking dependency" "$logf"; then
  die "lockdep PROVED a lock-ordering cycle (no hang needed — read the report above).
     The two chains show the two routines disagreeing about which lock comes first.
     Make module/d1_locks.c take the locks in ONE consistent order. README has hints."
elif grep -q "kernel-apprentice: d1_locks ran both maintenance routines" "$logf"; then
  ok "both routines ran and lockdep stayed silent — the lock order is consistent"
  ok "lesson D1 complete — you read a deadlock that hadn't happened yet"
else
  die "no lockdep splat, but the module never completed either (see $logf)"
fi
