#!/usr/bin/env bash
# Wheel — "Fast except sometimes" (LIVE FIRE).
#
# Boots the box you've been paged about: /proc/slowsvc (the "service") answers most
# requests instantly, but its p99 is awful. The scenario reproduces the symptom and
# confirms the diagnostic path works — function_graph localizes the slow request to
# slowsvc_read() and the sleep it detours through. (Your job, per the README: find it
# with the tracing tools before reading the source.)

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

log "building slowsvc.ko against $KERNEL_SRC"
make -C "$HERE" KDIR="$KERNEL_SRC" >/dev/null
ko="$HERE/slowsvc.ko"
[ -f "$ko" ] || die "module build produced no slowsvc.ko"

work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
overlay="$work/overlay"; mkdir -p "$overlay"
cp "$ko" "$overlay/slowsvc.ko"
cat > "$overlay/init" <<'INIT'
#!/bin/busybox sh
busybox mount -t proc     none /proc
busybox mount -t sysfs    none /sys
busybox mount -t devtmpfs none /dev 2>/dev/null
T=/sys/kernel/tracing
busybox mount -t tracefs nodev "$T" 2>/dev/null
insmod /slowsvc.ko

echo "=== graph the service handler across 10 requests ==="
echo nop > "$T/current_tracer"
echo slowsvc_read > "$T/set_graph_function"
echo function_graph > "$T/current_tracer"
: > "$T/trace"
echo 1 > "$T/tracing_on"
i=0
while [ "$i" -lt 10 ]; do busybox cat /proc/slowsvc >/dev/null 2>&1; i=$((i + 1)); done
echo 0 > "$T/tracing_on"
echo "--- function_graph: every slowsvc_read() and its duration ---"
busybox grep -E "slowsvc_read|msleep|schedule" "$T/trace" | busybox head -n 40
echo nop > "$T/current_tracer"
rmmod slowsvc
echo "APPRENTICE-DONE"
busybox poweroff -f
INIT
chmod +x "$overlay/init"

img="$work/initramfs.cpio.gz"
mk_initramfs "$img" "$overlay"

logf="$work/serial.log"
"$ROOT/harness/run-qemu.sh" "$img" --timeout 120 --log "$logf"

grep -q "slowsvc_read" "$logf" \
  || die "function_graph never showed slowsvc_read — did the service load? (see $logf)"
ok "the service handler slowsvc_read() is the request path"
# The graph is scoped to slowsvc_read's subtree, so a sleep here means a slow request
# detoured through it — that's the p99 tail.
if grep -qE "\b(msleep|schedule_timeout)\b" "$logf"; then
  ok "the slow requests detour through a sleep inside slowsvc_read — there's your p99"
else
  die "no slow path visible under slowsvc_read (expected a sleep on the slow requests) — see $logf"
fi
ok "Wheel reproduced: fast median, slow tail — localized to slowsvc_read"
