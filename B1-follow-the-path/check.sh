#!/usr/bin/env bash
# Lesson B1 check — "Follow the path" (READY).
#
# Drives the live kernel's ftrace WITHOUT a rebuild to answer "what calls what":
#   A) function_graph — the nested call GRAPH rooted at a function, with per-call time
#   B) set_ftrace_filter with a WILDCARD — narrow the firehose to *getpid*
#   C) func_stack_trace — WHO CALLS IT (the caller chain up to the syscall entry)
#   D) trace vs trace_pipe — a re-readable snapshot vs a draining stream
# Grades (READY, green out of the box):
#   PASS iff the log shows the function_graph view AND a caller stack.

set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$HERE"; while [ ! -d "$ROOT/harness" ] && [ "$ROOT" != / ]; do ROOT="$(dirname "$ROOT")"; done
# shellcheck source=../harness/lib.sh
source "$ROOT/harness/lib.sh"
# shellcheck source=../harness/initramfs.sh
source "$ROOT/harness/initramfs.sh"
assert_in_container
need gcc

ensure_kernel

work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
gcc -static -O2 -o "$work/trigger" "$HERE/trigger.c"
overlay="$work/overlay"; mkdir -p "$overlay"
cp "$work/trigger" "$overlay/trigger"
cat > "$overlay/init" <<'INIT'
#!/bin/busybox sh
busybox mount -t proc     none /proc
busybox mount -t sysfs    none /sys
busybox mount -t devtmpfs none /dev 2>/dev/null
T=/sys/kernel/tracing
busybox mount -t tracefs nodev "$T" 2>/dev/null
SYM=__do_sys_getpid

echo "=== A) function_graph — the call GRAPH rooted at $SYM (nesting + per-call time) ==="
echo nop > "$T/current_tracer"
echo "$SYM" > "$T/set_graph_function" 2>/dev/null
echo function_graph > "$T/current_tracer"
: > "$T/trace"
echo 1 > "$T/tracing_on"; /trigger; echo 0 > "$T/tracing_on"
busybox grep -E "getpid|DURATION|FUNCTION" "$T/trace" | busybox head -n 12
echo > "$T/set_graph_function" 2>/dev/null
echo nop > "$T/current_tracer"

echo
echo "=== B) set_ftrace_filter WILDCARD — every function matching *getpid* ==="
echo function > "$T/current_tracer"
echo '*getpid*' > "$T/set_ftrace_filter"
echo "   set_ftrace_filter resolved the wildcard to:"
busybox cat "$T/set_ftrace_filter"
: > "$T/trace"
echo 1 > "$T/tracing_on"; /trigger; echo 0 > "$T/tracing_on"
echo "   and the function tracer caught:"
busybox grep "getpid" "$T/trace" | busybox head -n 4

echo
echo "=== C) WHO CALLS IT — '<-' is the immediate caller; func_stack_trace gives the whole stack ==="
echo 1 > "$T/options/func_stack_trace"
: > "$T/trace"
echo 1 > "$T/tracing_on"; /trigger; echo 0 > "$T/tracing_on"
busybox grep -E "getpid|=>" "$T/trace" | busybox head -n 10
echo 0 > "$T/options/func_stack_trace"
echo > "$T/set_ftrace_filter"
echo nop > "$T/current_tracer"

echo
echo "=== D) trace vs trace_pipe — 'trace' is a re-readable snapshot (trace_pipe would drain) ==="
echo "   lines now sitting in the static 'trace' buffer: $(busybox wc -l < "$T/trace")"
echo "APPRENTICE-DONE"
busybox poweroff -f
INIT
chmod +x "$overlay/init"

img="$work/initramfs.cpio.gz"
mk_initramfs "$img" "$overlay"

logf="$work/serial.log"
"$ROOT/harness/run-qemu.sh" "$img" --timeout 90 --log "$logf"

grep -q "__do_sys_getpid()" "$logf" \
  || die "no function_graph view of the call path (expected '__do_sys_getpid()') — see $logf"
ok "A — function_graph showed the call path rooted at __do_sys_getpid"

if grep -q "=> do_syscall_64" "$logf"; then
  ok "C — func_stack_trace named the caller chain up to do_syscall_64"
elif grep -qE "=>.*getpid" "$logf"; then
  ok "C — func_stack_trace emitted the caller stack"
else
  die "no caller stack from func_stack_trace (expected '=> ...') — see $logf"
fi

grep -q "__x64_sys_getpid" "$logf" \
  && ok "B — the *getpid* wildcard resolved to more than one function"
ok "lesson B1 complete — you followed the path: graph, wildcard filter, caller stack"
