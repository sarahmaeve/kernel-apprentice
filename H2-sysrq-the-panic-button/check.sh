#!/usr/bin/env bash
# Lesson H2 check — "SysRq: the panic button" (READY).
#
# Builds h2_wedge.ko (parks a kthread in D state), boots a guest that walks the
# SysRq letters — t (all tasks), w (blocked tasks), m (memory), l (CPU
# backtraces) — reads the wedged thread's /proc/<pid>/stack, then presses the
# real panic button (sysrq c): the guest panics and QEMU exits (panic=-1 +
# -no-reboot, by harness design — no poweroff on this one).
# Grades (READY, green out of the box): PASS iff each dump appears, the D-state
# thread is visible with h2_wedge_fn in its stack, and the panic fired.

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

log "building h2_wedge.ko against $KERNEL_SRC"
make -C "$HERE/module" KDIR="$KERNEL_SRC" >/dev/null
ko="$HERE/module/h2_wedge.ko"
[ -f "$ko" ] || die "module build produced no h2_wedge.ko"

work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
overlay="$work/overlay"; mkdir -p "$overlay"
cp "$ko" "$overlay/h2_wedge.ko"
cat > "$overlay/init" <<'INIT'
#!/bin/busybox sh
busybox mount -t proc     none /proc
busybox mount -t sysfs    none /sys
busybox mount -t devtmpfs none /dev 2>/dev/null
echo "=== insmod h2_wedge.ko — wedge a thread in D state, on purpose ==="
insmod /h2_wedge.ko
busybox sleep 1
echo
echo "=== sysrq t — every task: state + stack ==="
echo t > /proc/sysrq-trigger
echo
echo "=== sysrq w — only the blocked (D state) tasks ==="
echo w > /proc/sysrq-trigger
echo
echo "=== sysrq m — memory state ==="
echo m > /proc/sysrq-trigger
echo
echo "=== sysrq l — backtrace of all active CPUs ==="
echo l > /proc/sysrq-trigger
busybox sleep 1
echo
pid="$(busybox grep -l h2-wedged /proc/[0-9]*/comm 2>/dev/null | busybox head -n 1)"
pid="${pid#/proc/}"; pid="${pid%/comm}"
echo "=== /proc/$pid/stack — ask the wedged thread where it sleeps ==="
busybox cat "/proc/$pid/stack"
echo
echo "APPRENTICE-DONE"
echo "=== sysrq c — the actual panic button (the guest dies NOW) ==="
echo c > /proc/sysrq-trigger
echo "(never reached)"
INIT
chmod +x "$overlay/init"

img="$work/initramfs.cpio.gz"
mk_initramfs "$img" "$overlay"

logf="$work/serial.log"
"$ROOT/harness/run-qemu.sh" "$img" --timeout 120 --log "$logf"

grep -q "sysrq: Show State" "$logf" \
  || die "no 'sysrq: Show State' — did the t trigger fire? (see $logf)"
grep -qE "task:h2-wedged +state:D" "$logf" \
  || die "the task dump doesn't show h2-wedged in state D (see $logf)"
ok "t — full task dump, and h2-wedged sits in D (uninterruptible)"

grep -q "sysrq: Show Blocked State" "$logf" \
  || die "no 'sysrq: Show Blocked State' — did the w trigger fire? (see $logf)"
ok "w — the blocked-tasks view singles the wedged thread out"

grep -q "h2_wedge_fn" "$logf" \
  || die "no stack frame names h2_wedge_fn — neither w/t nor /proc/<pid>/stack shows
     where the thread is parked (see $logf)"
ok "stack — h2_wedge_fn named: you can see exactly where it sleeps"

grep -q "sysrq: Show Memory" "$logf" \
  || die "no 'sysrq: Show Memory' — did the m trigger fire? (see $logf)"
ok "m — memory state dumped"

grep -q "sysrq: Show backtrace of all active CPUs" "$logf" \
  || die "no 'sysrq: Show backtrace of all active CPUs' — did the l trigger fire? (see $logf)"
ok "l — per-CPU backtraces (what is ON the CPUs right now)"

grep -q "sysrq: Trigger a crash" "$logf" \
  || die "no 'sysrq: Trigger a crash' — the panic button wasn't pressed (see $logf)"
grep -q "Kernel panic - not syncing" "$logf" \
  || die "crash triggered but no 'Kernel panic - not syncing' line (see $logf)"
ok "c — the panic button: the kernel panics on command; the guest is gone"
ok "lesson H2 complete — you can pull state out of a wedged box"
