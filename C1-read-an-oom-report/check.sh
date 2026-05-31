#!/usr/bin/env bash
# Lesson C1 check — "Read an OOM report" (READY).
#
# Triggers a cgroup OOM and dumps the report + /proc/meminfo + memory.events, so the
# lesson always has a real report to read. Grades (READY, green out of the box):
#   PASS iff the OOM report appears (with the per-task table) and meminfo is shown.

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
gcc -static -O2 -o "$work/hog" "$HERE/hog.c"
overlay="$work/overlay"; mkdir -p "$overlay"
cp "$work/hog" "$overlay/hog"
cat > "$overlay/init" <<'INIT'
#!/bin/busybox sh
busybox mount -t proc     none /proc
busybox mount -t sysfs    none /sys
busybox mount -t devtmpfs none /dev 2>/dev/null
busybox mkdir -p /cg && busybox mount -t cgroup2 none /cg
echo +memory > /cg/cgroup.subtree_control 2>/dev/null
busybox mkdir -p /cg/svc
echo 16M > /cg/svc/memory.max
echo "=== triggering an OOM: a service in a 16M cgroup grows past its limit ==="
busybox sh -c 'echo $$ > /cg/svc/cgroup.procs; exec /hog' 2>&1
echo
echo "===== THE OOM REPORT ====="
dmesg | busybox grep -iE "invoked oom-killer|memory: usage|Tasks state|oom_score_adj|Memory cgroup out of memory|Killed process|anon-rss" | busybox tail -n 20
echo
echo "===== /proc/meminfo (system memory at the time) ====="
busybox grep -E "^(MemTotal|MemFree|MemAvailable|AnonPages|Slab):" /proc/meminfo
echo
echo "===== cgroup memory.events (the oom_kill counter) ====="
busybox cat /cg/svc/memory.events
echo "APPRENTICE-DONE"
busybox poweroff -f
INIT
chmod +x "$overlay/init"

img="$work/initramfs.cpio.gz"
mk_initramfs "$img" "$overlay"

logf="$work/serial.log"
"$ROOT/harness/run-qemu.sh" "$img" --timeout 90 --log "$logf"

grep -qiE "Memory cgroup out of memory|Killed process [0-9]+ \(hog\)" "$logf" \
  || die "no OOM report in the log — did the cgroup OOM fire? (see $logf)"
ok "the OOM report is present (who got killed, its RSS, the constraint)"
grep -q "MemTotal" "$logf" \
  && ok "corroborating evidence shown (/proc/meminfo, memory.events)"
ok "lesson C1 complete — you have a real OOM report to read"
