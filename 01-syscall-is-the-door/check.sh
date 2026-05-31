#!/usr/bin/env bash
# Lesson 01 check — "the syscall is the door".
#
# Rebuilds the kernel (incremental, to pick up the learner's printk in
# kernel/sys.c), boots a guest that runs `door` under strace, and grades:
#   PASS iff the serial log shows BOTH
#     * getpid(                          (strace: the boundary, observed)
#     * kernel-apprentice: getpid by door (the learner's printk, fired)

set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# Locate the repo root (the dir holding harness/) regardless of nesting depth.
ROOT="$HERE"; while [ ! -d "$ROOT/harness" ] && [ "$ROOT" != / ]; do ROOT="$(dirname "$ROOT")"; done
# shellcheck source=../harness/lib.sh
source "$ROOT/harness/lib.sh"
# shellcheck source=../harness/initramfs.sh
source "$ROOT/harness/initramfs.sh"
assert_in_container
need gcc

ensure_kernel

# Incremental rebuild — fast; picks up an edit to kernel/sys.c if there is one.
log "rebuilding kernel (incremental — picks up your kernel/sys.c edit)"
make -C "$KERNEL_SRC" ARCH="$GUEST_ARCH" -j"$(nproc)" bzImage >/dev/null

work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
gcc -static -O2 -o "$work/door" "$HERE/door.c"

overlay="$work/overlay"; mkdir -p "$overlay"
cp "$work/door" "$overlay/door"
cat > "$overlay/init" <<'INIT'
#!/bin/busybox sh
busybox mount -t proc     none /proc
busybox mount -t sysfs    none /sys
busybox mount -t devtmpfs none /dev 2>/dev/null
echo "=== view 1: strace (the boundary, observed) ==="
strace -f /door 2>&1 || echo "(strace failed)"
echo "=== view 3: dmesg (did your printk fire?) ==="
dmesg | grep -i kernel-apprentice || echo "(no kernel-apprentice line in dmesg)"
echo "APPRENTICE-DONE"
busybox poweroff -f
INIT
chmod +x "$overlay/init"

img="$work/initramfs.cpio.gz"
mk_initramfs "$img" "$overlay" strace      # bundle strace + its libs into the guest

logf="$work/serial.log"
"$ROOT/harness/run-qemu.sh" "$img" --timeout 90 --log "$logf"

grep -q "getpid(" "$logf" \
  || die "strace never showed getpid() — the guest didn't reach the boundary (see $logf)"
ok "view 1 — strace shows getpid() crossing the door"

if grep -q "kernel-apprentice: getpid by door" "$logf"; then
  ok "view 3 — your printk fired for the 'door' process"
  ok "lesson 01 complete: one event, three views"
else
  die "no 'kernel-apprentice: getpid by door' in the kernel log.
     Add the guarded pr_info to SYSCALL_DEFINE0(getpid) in kernel/sys.c, then re-run.
     See README.md (Touch / graduated hints)."
fi
