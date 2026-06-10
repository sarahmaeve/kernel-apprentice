#!/usr/bin/env bash
# Wheel scenario check — "The process that won't die".
#
# Boots a guest where the "service" (ticketd) journals through a vendor module
# whose compaction thread wedges holding the journal lock — so ticketd's first
# write parks it in uninterruptible D sleep, inside the syscall. kill -9 lands
# but is never delivered. Like the other wheels, this grades that the SCENARIO
# IS CORRECTLY ARMED (not the learner's diagnosis):
#   PASS iff ticketd is in D, survives SIGKILL, its stack names the module, and
#   khungtaskd reports it.
#
# Needs the Module D detector config in the base kernel (self-detects staleness).

set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$HERE"; while [ ! -d "$ROOT/harness" ] && [ "$ROOT" != / ]; do ROOT="$(dirname "$ROOT")"; done
# shellcheck source=../../harness/lib.sh
source "$ROOT/harness/lib.sh"
# shellcheck source=../../harness/initramfs.sh
source "$ROOT/harness/initramfs.sh"
assert_in_container
need make; need gcc

ensure_kernel

grep -q '^CONFIG_DETECT_HUNG_TASK=y' "$KERNEL_SRC/.config" \
  || die "this wheel needs the hung-task detector in the base kernel — Module D added
     it to harness/config/tutorial.config. Run 'make kernel' once to pick it up."

log "building vjournal.ko against $KERNEL_SRC"
make -C "$HERE" KDIR="$KERNEL_SRC" >/dev/null
[ -f "$HERE/vjournal.ko" ] || die "module build produced no vjournal.ko"

work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
gcc -static -O2 -o "$work/ticketd" "$HERE/ticketd.c"
overlay="$work/overlay"; mkdir -p "$overlay"
cp "$HERE/vjournal.ko" "$overlay/vjournal.ko"
cp "$work/ticketd" "$overlay/ticketd"
cat > "$overlay/init" <<'INIT'
#!/bin/busybox sh
busybox mount -t proc     none /proc
busybox mount -t sysfs    none /sys
busybox mount -t devtmpfs none /dev 2>/dev/null
insmod /vjournal.ko
echo 3 > /proc/sys/kernel/hung_task_timeout_secs
echo "=== starting ticketd (the service) ==="
/ticketd &
pid=$!
busybox sleep 3
echo
echo "=== requests have stopped; the supervisor tries the usual ==="
echo "--- kill -9 $pid ---"
busybox kill -9 $pid
busybox sleep 2
if [ -d /proc/$pid ]; then
  echo "ticketd ($pid) SURVIVED kill -9"
else
  echo "(ticketd actually died — scenario failed to arm)"
fi
echo
echo "=== diagnosis surface ==="
echo "--- /proc/$pid/status ---"
busybox grep -E '^(Name|State|SigPnd)' /proc/$pid/status
echo "--- /proc/$pid/stack ---"
busybox cat /proc/$pid/stack
echo
echo "--- waiting for the kernel's own detector (khungtaskd) ---"
busybox sleep 7
dmesg | busybox grep -B1 -A14 "blocked for more than" | busybox tail -n 70
echo "APPRENTICE-DONE"
busybox poweroff -f
INIT
chmod +x "$overlay/init"

img="$work/initramfs.cpio.gz"
mk_initramfs "$img" "$overlay"

logf="$work/serial.log"
"$ROOT/harness/run-qemu.sh" "$img" --timeout 120 --log "$logf"

grep -q "ticketd: journaling ticket 1" "$logf" \
  || die "the service never started (see $logf)"
grep -q "ticketd: ticket 1 committed" "$logf" \
  && die "ticket 1 COMMITTED — the journal lock isn't wedged; scenario failed to arm (see $logf)"
ok "symptom reproduced: ticketd froze mid-request (journaling, never committed)"

grep -q "SURVIVED kill -9" "$logf" \
  || die "ticketd did not survive SIGKILL — the D-state wedge didn't arm (see $logf)"
grep -qE "State:.*D" "$logf" \
  || die "ticketd isn't in D (uninterruptible) state (see $logf)"
ok "evidence present: state D, and kill -9 lands but is never delivered"

grep -q "vjournal_write" "$logf" \
  || die "/proc/<pid>/stack doesn't name the vendor module's write path (see $logf)"
grep -qE "INFO: task (ticketd|vjournal-compact):[0-9]+ blocked for more than" "$logf" \
  || die "khungtaskd never reported the stuck task(s) (see $logf)"
ok "evidence present: the stack points into vjournal, and khungtaskd reported it unprompted"
ok "wheel scenario correctly armed"
