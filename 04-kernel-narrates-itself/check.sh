#!/usr/bin/env bash
# Lesson 04 check — "the kernel narrates itself".
#
# Attaches dynamic tracing to the LIVE kernel with NO rebuild: the ftrace function
# tracer and a kprobe on __do_sys_getpid (the very handler edited in lesson 01),
# both via tracefs, then triggers a getpid. Grades:
#   PASS iff the serial log shows the kprobe fired:  ka_getpid:

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

echo "=== view 1: the function tracer narrates $SYM being called (no rebuild) ==="
echo "$SYM" > "$T/set_ftrace_filter" 2>/dev/null
echo function > "$T/current_tracer" 2>/dev/null
: > "$T/trace"
echo 1 > "$T/tracing_on"
/trigger
echo 0 > "$T/tracing_on"
busybox grep "$SYM" "$T/trace" | busybox head -n 2
echo nop > "$T/current_tracer" 2>/dev/null
echo > "$T/set_ftrace_filter" 2>/dev/null

echo "=== view 3: attach a kprobe to the SAME function, live, no rebuild ==="
echo "p:ka_getpid $SYM" > "$T/kprobe_events" 2>&1
echo 1 > "$T/events/kprobes/ka_getpid/enable" 2>/dev/null
: > "$T/trace"
echo 1 > "$T/tracing_on"
/trigger
echo 0 > "$T/tracing_on"
busybox grep "ka_getpid:" "$T/trace" | busybox head -n 2
echo 0 > "$T/events/kprobes/ka_getpid/enable" 2>/dev/null
echo "-:ka_getpid" > "$T/kprobe_events" 2>/dev/null
echo "APPRENTICE-DONE"
busybox poweroff -f
INIT
chmod +x "$overlay/init"

img="$work/initramfs.cpio.gz"
mk_initramfs "$img" "$overlay"

logf="$work/serial.log"
"$ROOT/harness/run-qemu.sh" "$img" --timeout 90 --log "$logf"

grep -q "ka_getpid:" "$logf" \
  || die "the kprobe never fired on __do_sys_getpid (see $logf).
     Check the symbol name in 'make shell':
       grep ' __do_sys_getpid$' /proc/kallsyms
       grep getpid /sys/kernel/tracing/available_filter_functions"
ok "view 3 — a kprobe fired on __do_sys_getpid, attached to the LIVE kernel (no rebuild)"
if grep -q "__do_sys_getpid <-" "$logf"; then
  ok "view 1 — the function tracer also narrated the same call"
else
  warn "function tracer view didn't show (non-fatal; the kprobe is the lesson)"
fi
ok "lesson 04 complete"
