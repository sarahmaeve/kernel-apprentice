#!/usr/bin/env bash
# Lesson B4 check — "Events & histograms" (CHALLENGE).
#
# Drives the tracepoint events interface, then aggregates with a hist trigger that
# YOU write. The check applies your trigger.hist to raw_syscalls/sys_enter, runs a
# workload, and reads the histogram. Grades:
#   PASS iff the histogram is bucketed by syscall id (lines like "{ id: N }").
# The shipped trigger.hist has keys=___ (an invalid field), so the kernel rejects it
# and there is no histogram — RED until you key it by the right field.
#
# Needs CONFIG_HIST_TRIGGERS (Module B). Self-detects a stale kernel and says so.

set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$HERE"; while [ ! -d "$ROOT/harness" ] && [ "$ROOT" != / ]; do ROOT="$(dirname "$ROOT")"; done
# shellcheck source=../harness/lib.sh
source "$ROOT/harness/lib.sh"
# shellcheck source=../harness/initramfs.sh
source "$ROOT/harness/initramfs.sh"
assert_in_container

ensure_kernel

grep -q "^CONFIG_HIST_TRIGGERS=y" "$KERNEL_SRC/.config" 2>/dev/null || die "your kernel is missing
   CONFIG_HIST_TRIGGERS — it predates Module B. Run 'make kernel' to rebuild with the
   current config, then retry. (B1/B2 run on the stock kernel; B3/B4 need this.)"

# Pull the learner's hist expression out of trigger.hist (first non-comment hist: line).
hist_expr="$(grep -E '^hist:' "$HERE/trigger.hist" | head -n1)"
[ -n "$hist_expr" ] || die "no 'hist:...' line found in trigger.hist"

work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
overlay="$work/overlay"; mkdir -p "$overlay"
printf '%s\n' "$hist_expr" > "$overlay/trigger.hist"
cat > "$overlay/init" <<'INIT'
#!/bin/busybox sh
busybox mount -t proc     none /proc
busybox mount -t sysfs    none /sys
busybox mount -t devtmpfs none /dev 2>/dev/null
T=/sys/kernel/tracing
busybox mount -t tracefs nodev "$T" 2>/dev/null
E="$T/events/raw_syscalls/sys_enter"

workload() {
	i=0
	while [ "$i" -lt 8 ]; do
		busybox cat /proc/meminfo /proc/loadavg /proc/self/stat >/dev/null 2>&1
		busybox ls -l /sys/class /sys/block >/dev/null 2>&1
		i=$((i + 1))
	done
}

echo "=== A) the events interface — every tracepoint has a 'format' (its fields) ==="
busybox grep -E "^\s+field:" "$E/format" | busybox head -n 6

echo
echo "=== B) your hist trigger (from trigger.hist) ==="
HIST="$(busybox cat /trigger.hist)"
echo "applying: $HIST"
echo "$HIST" > "$E/trigger" 2>&1 || echo "(the kernel rejected that trigger expression)"
echo 1 > "$E/enable"
workload
echo 0 > "$E/enable"
echo "--- the histogram (cat .../sys_enter/hist) ---"
busybox cat "$E/hist" 2>/dev/null | busybox head -n 22

echo
echo "=== C) the rest of the interface (try these in make shell) ==="
echo "filter:        echo 'id == 257' > $E/filter      # only openat"
echo "set_event_pid: echo \$\$ > $T/set_event_pid       # scope to one task"
echo "APPRENTICE-DONE"
busybox poweroff -f
INIT
chmod +x "$overlay/init"

img="$work/initramfs.cpio.gz"
mk_initramfs "$img" "$overlay"

logf="$work/serial.log"
"$ROOT/harness/run-qemu.sh" "$img" --timeout 120 --log "$logf"

grep -q "{ id:" "$logf" || die "the histogram isn't bucketed by syscall id (no '{ id: N }' rows).
   Set the key in trigger.hist to the syscall-number field (the lesson hints have it). (log: $logf)"
ok "your hist trigger bucketed every syscall by id"
grep -qE "Totals:|Hits:" "$logf" \
  && ok "the histogram tallied totals across the run"
ok "lesson B4 complete — you read a tracepoint's format and aggregated it with a hist trigger"
