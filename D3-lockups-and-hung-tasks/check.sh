#!/usr/bin/env bash
# Lesson D3 check — "lockups & hung tasks" (READY).
#
# Builds the stall specimen, boots a guest that lowers the detector thresholds
# (watchdog_thresh, hung_task_timeout_secs — the same knobs production tunes),
# then stalls a CPU (soft lockup) and parks a thread in D (hung task) so both
# detectors fire. Grades (READY, green out of the box): PASS iff both reports
# appear and name the specimen.
#
# Runs on the BASE kernel but needs the Module D config additions
# (SOFTLOCKUP_DETECTOR, DETECT_HUNG_TASK) — self-detects a stale kernel.

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

grep -q '^CONFIG_SOFTLOCKUP_DETECTOR=y' "$KERNEL_SRC/.config" \
  && grep -q '^CONFIG_DETECT_HUNG_TASK=y' "$KERNEL_SRC/.config" \
  || die "this lesson needs the stall detectors in the base kernel — Module D added
     them to harness/config/tutorial.config. Run 'make kernel' once to pick them up
     (re-merges the config; incremental rebuild)."

log "building d3_stall.ko against $KERNEL_SRC"
make -C "$HERE/module" KDIR="$KERNEL_SRC" >/dev/null
ko="$HERE/module/d3_stall.ko"
[ -f "$ko" ] || die "module build produced no d3_stall.ko"

work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
overlay="$work/overlay"; mkdir -p "$overlay"
cp "$ko" "$overlay/d3_stall.ko"
cat > "$overlay/init" <<'INIT'
#!/bin/busybox sh
busybox mount -t proc     none /proc
busybox mount -t sysfs    none /sys
busybox mount -t devtmpfs none /dev 2>/dev/null
echo "=== insmod d3_stall.ko + lower the detector thresholds ==="
insmod /d3_stall.ko
echo 2 > /proc/sys/kernel/watchdog_thresh
echo 3 > /proc/sys/kernel/hung_task_timeout_secs
echo "(watchdog_thresh=2s -> soft lockup fires at ~4s; hung_task_timeout=3s)"
echo
echo "=== 1/2 soft lockup: hog a CPU with preemption disabled ==="
busybox sh -c 'echo spin > /proc/d3-stall'
busybox sleep 1
echo
echo "=== 2/2 hung task: park a thread in D and let khungtaskd find it ==="
busybox sh -c 'echo hang > /proc/d3-stall'
busybox sleep 8
echo
echo "===== THE TWO REPORTS (dmesg) ====="
dmesg | busybox grep -B2 -A22 -E "soft lockup|blocked for more than" | busybox tail -n 90
echo "APPRENTICE-DONE"
busybox poweroff -f
INIT
chmod +x "$overlay/init"

img="$work/initramfs.cpio.gz"
mk_initramfs "$img" "$overlay"

logf="$work/serial.log"
"$ROOT/harness/run-qemu.sh" "$img" --timeout 120 --log "$logf"

grep -q "BUG: soft lockup" "$logf" \
  || die "no soft-lockup report — did the spin run long enough past watchdog_thresh? (see $logf)"
grep -qE "RIP: 0010:.*\[d3_stall\]" "$logf" \
  || die "soft lockup fired but its RIP doesn't point into d3_stall (see $logf)"
ok "report 1/2 — soft lockup: the watchdog names the hogged CPU and the spinning code"

grep -q "kernel-apprentice: d3 spin done" "$logf" \
  || die "the spin never completed — the CPU stayed wedged (see $logf)"
ok "the CPU recovered — a soft lockup is a report, not a crash"

grep -qE "INFO: task d3-hung:[0-9]+ blocked for more than" "$logf" \
  || die "no hung-task report — did khungtaskd run with the lowered timeout? (see $logf)"
grep -q "d3_hung_fn" "$logf" \
  || die "hung-task report present but its stack doesn't name d3_hung_fn (see $logf)"
ok "report 2/2 — khungtaskd: the D-state thread named, with the stack that parked it"
ok "lesson D3 complete — the kernel's stall detectors reported both stalls to you"
