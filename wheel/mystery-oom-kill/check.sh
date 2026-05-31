#!/usr/bin/env bash
# Wheel scenario check — "Mystery OOM kill".
#
# Boots a guest that puts the "service" (hog) in a cgroup with a small memory.max,
# so it grows past the limit and the cgroup OOM killer reaps it. Like works-on-my-
# laptop, this grades that the SCENARIO IS CORRECTLY ARMED (not the learner's
# diagnosis): the OOM reproduces and its report is present.
#   PASS iff the log shows a cgroup OOM kill of the service.

set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$HERE"; while [ ! -d "$ROOT/harness" ] && [ "$ROOT" != / ]; do ROOT="$(dirname "$ROOT")"; done
# shellcheck source=../../harness/lib.sh
source "$ROOT/harness/lib.sh"
# shellcheck source=../../harness/initramfs.sh
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
# cgroup v2 — production mounts it at /sys/fs/cgroup; the lean guest uses /cg.
busybox mkdir -p /cg
busybox mount -t cgroup2 none /cg || echo "(cgroup2 mount failed)"
echo +memory > /cg/cgroup.subtree_control 2>/dev/null || echo "(no memory controller)"
busybox mkdir -p /cg/svc
echo 16M > /cg/svc/memory.max 2>/dev/null
echo "=== svc cgroup memory.max = $(busybox cat /cg/svc/memory.max 2>/dev/null) ==="
echo "=== launching the service inside the constrained cgroup ==="
# sh -c so $$ is THIS child's pid; join the cgroup, then become the hog.
busybox sh -c 'echo $$ > /cg/svc/cgroup.procs; exec /hog' 2>&1
echo "(service exited)"
echo "=== dmesg: the OOM report (who got killed, and why) ==="
dmesg | busybox grep -iE "invoked oom-killer|Memory cgroup out of memory|Killed process|anon-rss" | busybox tail -n 15
echo "=== /cg/svc/memory.events ==="
busybox cat /cg/svc/memory.events 2>/dev/null
echo "APPRENTICE-DONE"
busybox poweroff -f
INIT
chmod +x "$overlay/init"

img="$work/initramfs.cpio.gz"
mk_initramfs "$img" "$overlay"

logf="$work/serial.log"
"$ROOT/harness/run-qemu.sh" "$img" --timeout 90 --log "$logf"

# Require a CGROUP OOM specifically (constraint=CONSTRAINT_MEMCG), so a mere global
# OOM (the box running out of RAM) doesn't masquerade as the scenario.
if grep -qiE "Memory cgroup out of memory|constraint=CONSTRAINT_MEMCG" "$logf"; then
  ok "symptom reproduced: the service was OOM-killed by its CGROUP memory limit"
  grep -qiE "Killed process [0-9]+ \(hog\)" "$logf" \
    && ok "evidence present: the OOM report names the victim (hog), its RSS, and the cgroup"
  ok "wheel scenario correctly armed"
else
  die "no CGROUP OOM in the log — the memory controller didn't arm (CONFIG_MEMCG? cgroup setup?). See $logf"
fi
