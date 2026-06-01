#!/usr/bin/env bash
# Lesson B2 check — "Trace just what matters" (CHALLENGE).
#
# Builds b2_worker.ko, then isolates ITS signal out of the whole-kernel firehose:
#   * per-module filter   echo :mod:b2_worker > set_ftrace_filter
#   * per-pid filter      echo $$ > set_ftrace_pid   (only the triggering task)
#   * trace_marker        userspace brackets the run from inside the trace
#   * tracing_on          enable/disable around the window
# Grades:
#   PASS iff the trace shows all three markers: "b2: parse", "b2: compute",
#        "b2: emit". The shipped module emits none of them, so it's RED until you
#        instrument all three phases.

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

log "building b2_worker.ko against $KERNEL_SRC"
make -C "$HERE/module" KDIR="$KERNEL_SRC" >/dev/null
ko="$HERE/module/b2_worker.ko"
[ -f "$ko" ] || die "module build produced no b2_worker.ko"

work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
overlay="$work/overlay"; mkdir -p "$overlay"
cp "$ko" "$overlay/b2_worker.ko"
cat > "$overlay/init" <<'INIT'
#!/bin/busybox sh
busybox mount -t proc     none /proc
busybox mount -t sysfs    none /sys
busybox mount -t devtmpfs none /dev 2>/dev/null
T=/sys/kernel/tracing
busybox mount -t tracefs nodev "$T" 2>/dev/null
insmod /b2_worker.ko

echo "=== isolate: per-module filter — trace ONLY b2_worker's functions ==="
echo nop > "$T/current_tracer"
echo ':mod:b2_worker' > "$T/set_ftrace_filter"
echo "   set_ftrace_filter resolved :mod:b2_worker to:"
busybox cat "$T/set_ftrace_filter"
echo function > "$T/current_tracer"

echo "=== run it, scoped to this PID, bracketed with trace_marker, gated by tracing_on ==="
: > "$T/trace"
echo $$ > "$T/set_ftrace_pid"
echo 1 > "$T/tracing_on"
echo "=== b2 run start ===" > "$T/trace_marker"
echo go > /proc/b2-go
echo "=== b2 run end ===" > "$T/trace_marker"
echo 0 > "$T/tracing_on"

echo "=== the isolated trace (marker + per-module funcs + the worker's trace_printk) ==="
busybox grep -E "b2 run|b2:|phase_" "$T/trace" | busybox head -n 25

echo nop > "$T/current_tracer"
echo > "$T/set_ftrace_filter"
rmmod b2_worker
echo "APPRENTICE-DONE"
busybox poweroff -f
INIT
chmod +x "$overlay/init"

img="$work/initramfs.cpio.gz"
mk_initramfs "$img" "$overlay"

logf="$work/serial.log"
"$ROOT/harness/run-qemu.sh" "$img" --timeout 90 --log "$logf"

# Each phase must narrate the trace via trace_printk.
for m in "b2: parse" "b2: compute" "b2: emit"; do
  grep -q "$m" "$logf" || die "the trace is missing \"$m\" — make that phase write it in
     module/b2_worker.c (the lesson hints show how). (log: $logf)"
done
ok "all three phases narrate the trace (b2: parse / compute / emit)"

grep -q "phase_compute" "$logf" \
  && ok "the per-module filter (:mod:b2_worker) isolated the worker's own functions"
grep -q "b2 run start" "$logf" \
  && ok "trace_marker bracketed the run from userspace"
ok "lesson B2 complete — you instrumented with trace_printk and isolated the signal"
