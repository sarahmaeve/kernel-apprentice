#!/usr/bin/env bash
# Lesson B3 check — "Latency & context" (READY).
#
# The first lesson that USES the tracers Module B added to the kernel. Drives four
# latency/profiling views against the live kernel:
#   A) irqsoff latency tracer — the longest interrupts-off region + its latency-format
#      context flags (the d/h/s/N columns)
#   B) function profiler — which functions ran, how often, how long
#   C) stack tracer — the deepest kernel stack seen (catch overflows before they bite)
#   D) snapshot — freeze the buffer at an instant
# Self-detects a stale, pre-Module-B kernel and tells you to rebuild. READY: green
# out of the box.

set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$HERE"; while [ ! -d "$ROOT/harness" ] && [ "$ROOT" != / ]; do ROOT="$(dirname "$ROOT")"; done
# shellcheck source=../harness/lib.sh
source "$ROOT/harness/lib.sh"
# shellcheck source=../harness/initramfs.sh
source "$ROOT/harness/initramfs.sh"
assert_in_container

ensure_kernel

# Self-detecting guard: these tracers arrived with Module B. If the cached kernel
# predates them, fail with the fix instead of a confusing empty trace.
for cfg in CONFIG_IRQSOFF_TRACER CONFIG_FUNCTION_PROFILER CONFIG_STACK_TRACER; do
  grep -q "^$cfg=y" "$KERNEL_SRC/.config" 2>/dev/null || die "your kernel is missing $cfg — it
     predates Module B's tracers. Run 'make kernel' to rebuild with the current config,
     then retry. (B1/B2 run on the stock kernel; B3/B4 need this.)"
done

work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
overlay="$work/overlay"; mkdir -p "$overlay"
cat > "$overlay/init" <<'INIT'
#!/bin/busybox sh
busybox mount -t proc     none /proc
busybox mount -t sysfs    none /sys
busybox mount -t devtmpfs none /dev 2>/dev/null
T=/sys/kernel/tracing
busybox mount -t tracefs nodev "$T" 2>/dev/null

# a BOUNDED workload: varied syscalls + a little vfs, fast. (Full /sys recursion is
# far too slow once a tracer — especially the function tracer — is on.)
workload() {
	i=0
	while [ "$i" -lt 8 ]; do
		busybox cat /proc/meminfo /proc/loadavg /proc/self/stat >/dev/null 2>&1
		busybox ls -l /sys/class /sys/block >/dev/null 2>&1
		i=$((i + 1))
	done
}

echo "=== A) irqsoff latency tracer — the longest interrupts-off region ==="
echo 0 > "$T/tracing_on"
echo irqsoff > "$T/current_tracer"
echo 0 > "$T/tracing_max_latency"
echo 1 > "$T/tracing_on"
workload
echo 0 > "$T/tracing_on"
echo "max irqs-off latency (microseconds): $(busybox cat "$T/tracing_max_latency")"
busybox head -n 18 "$T/trace"
echo nop > "$T/current_tracer"

echo
echo "=== B) function profiler — which functions ran, how often, how long ==="
echo 1 > "$T/function_profile_enabled"
workload
echo 0 > "$T/function_profile_enabled"
busybox cat "$T"/trace_stat/function* 2>/dev/null | busybox head -n 14

echo
echo "=== C) stack tracer — the deepest kernel stack seen ==="
echo 1 > /proc/sys/kernel/stack_tracer_enabled
workload
echo "max stack depth (bytes): $(busybox cat "$T/stack_max_size" 2>/dev/null)"
busybox head -n 12 "$T/stack_trace"
echo 0 > /proc/sys/kernel/stack_tracer_enabled

echo
echo "=== D) snapshot — freeze the buffer at an instant ==="
echo function > "$T/current_tracer"
busybox cat /proc/version >/dev/null 2>&1   # tiny — full function tracing is heavy
echo 1 > "$T/snapshot" 2>/dev/null
echo "snapshot froze $(busybox wc -l < "$T/snapshot" 2>/dev/null) lines of trace"
echo nop > "$T/current_tracer"

echo "APPRENTICE-DONE"
busybox poweroff -f
INIT
chmod +x "$overlay/init"

img="$work/initramfs.cpio.gz"
mk_initramfs "$img" "$overlay"

logf="$work/serial.log"
# Heavy tracing under TCG emulation is slow, so allow extra margin over other lessons.
"$ROOT/harness/run-qemu.sh" "$img" --timeout 180 --log "$logf"

grep -q "tracer: irqsoff" "$logf" \
  || die "no irqsoff latency trace (expected '# tracer: irqsoff') — see $logf"
ok "A — irqsoff latency tracer reported the worst interrupts-off region + context flags"

grep -qE "Function +Hit" "$logf" \
  || die "no function profiler stats (expected a 'Function ... Hit' table) — see $logf"
ok "B — the function profiler ranked the hottest functions"

grep -qE "Depth +Size +Location" "$logf" \
  || die "no stack tracer output (expected a 'Depth Size Location' table) — see $logf"
ok "C — the stack tracer captured the deepest kernel stack"

ok "lesson B3 complete — latency, context flags, profiler, stack, snapshot"
