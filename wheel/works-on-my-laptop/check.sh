#!/usr/bin/env bash
# Wheel scenario check — "Works on my laptop".
#
# Boots the deliberately-broken guest (low RLIMIT_NOFILE) and runs svc under
# strace. This grades that the SCENARIO IS CORRECTLY ARMED — not the learner's
# diagnosis — i.e. the box is broken exactly the way the page describes:
#   PASS iff the serial log shows BOTH
#     * the EMFILE failure ("Too many open files")   — symptom reproduces
#     * a low "Max open files" limit in /proc          — ground-truth evidence exists

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
gcc -static -O2 -o "$work/svc" "$HERE/svc.c"

overlay="$work/overlay"; mkdir -p "$overlay"
cp "$work/svc" "$overlay/svc"
# The fault injection: a prod-shaped low file-descriptor ceiling. Nothing touches
# the binary — only the environment the kernel hands it.
cat > "$overlay/init" <<'INIT'
#!/bin/busybox sh
busybox mount -t proc     none /proc
busybox mount -t sysfs    none /sys
busybox mount -t devtmpfs none /dev 2>/dev/null

ulimit -n 64    # <-- injected fault: far below what svc needs (the laptop has more)

echo "=== /proc/self/limits (the kernel-enforced ceiling) ==="
cat /proc/self/limits | grep 'open files'
echo "=== svc under strace (watch the boundary) ==="
strace -f /svc 2>&1 | tail -n 15
echo "APPRENTICE-DONE"
busybox poweroff -f
INIT
chmod +x "$overlay/init"

img="$work/initramfs.cpio.gz"
mk_initramfs "$img" "$overlay" strace

logf="$work/serial.log"
"$ROOT/harness/run-qemu.sh" "$img" --timeout 90 --log "$logf"

grep -Eq "EMFILE|Too many open files" "$logf" \
  || die "scenario did not reproduce the EMFILE failure (see $logf)"
ok "symptom reproduced: svc hits EMFILE at the syscall boundary"
grep -q "Max open files" "$logf" \
  || die "ground-truth evidence (/proc limits) not visible (see $logf)"
ok "evidence present: the low open-files ceiling is visible in /proc"
ok "wheel scenario correctly armed"
