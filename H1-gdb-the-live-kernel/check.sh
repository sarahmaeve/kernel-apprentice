#!/usr/bin/env bash
# Lesson H1 — step through the live kernel with gdb (via QEMU's gdbstub).
#
# Boots the guest FROZEN with a gdb stub (-S -gdb), attaches gdb to vmlinux, sets a
# breakpoint on __do_sys_getpid (the lesson-01 handler), continues until a getpid
# syscall hits it, and dumps the backtrace — driving the running kernel, no rebuild.
#   PASS iff gdb's breakpoint actually HITS at __do_sys_getpid.
#
# Note: boots with `nokaslr` so vmlinux's static symbol addresses match the running
# kernel. The base kernel has no CONFIG_DEBUG_INFO yet, so gdb shows function names
# + offsets (not source lines); that upgrade comes with the oops/crash module.

set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$HERE"; while [ ! -d "$ROOT/harness" ] && [ "$ROOT" != / ]; do ROOT="$(dirname "$ROOT")"; done
# shellcheck source=../harness/lib.sh
source "$ROOT/harness/lib.sh"
# shellcheck source=../harness/initramfs.sh
source "$ROOT/harness/initramfs.sh"
assert_in_container
need qemu-system-x86_64; need gdb; need gcc

ensure_kernel
VMLINUX="$KERNEL_SRC/vmlinux"
[ -f "$VMLINUX" ] || die "no vmlinux at $VMLINUX — build the kernel first"

work="$(mktemp -d)"
qpid=""
cleanup() { [ -n "$qpid" ] && kill "$qpid" 2>/dev/null; rm -rf "$work"; }
trap cleanup EXIT

gcc -static -O2 -o "$work/trigger" "$HERE/trigger.c"
overlay="$work/overlay"; mkdir -p "$overlay"
cp "$work/trigger" "$overlay/trigger"
cat > "$overlay/init" <<'INIT'
#!/bin/busybox sh
busybox mount -t proc     none /proc
busybox mount -t devtmpfs none /dev 2>/dev/null
/trigger          # fire getpid so the gdb breakpoint hits
busybox poweroff -f
INIT
chmod +x "$overlay/init"
img="$work/initramfs.cpio.gz"
mk_initramfs "$img" "$overlay"

port=1234
log "booting guest FROZEN with a gdb stub on :$port (nokaslr so symbols line up)"
timeout 120 qemu-system-x86_64 \
  -accel tcg -no-reboot -nographic -m 512M -smp 1 \
  -kernel "$KERNEL_BZIMAGE" -initrd "$img" \
  -append "console=ttyS0 panic=-1 nokaslr" \
  -S -gdb "tcp::$port" </dev/null >"$work/qemu.log" 2>&1 &
qpid=$!

# Wait for the gdb stub to accept a connection.
for _ in $(seq 1 40); do
  (exec 3<>"/dev/tcp/127.0.0.1/$port") 2>/dev/null && { exec 3>&-; break; }
  sleep 0.25
done

log "attaching gdb, breaking on __do_sys_getpid, continuing until it fires"
gdblog="$work/gdb.log"
timeout 90 gdb -batch -nx \
  -ex "set pagination off" \
  -ex "target remote :$port" \
  -ex "break __do_sys_getpid" \
  -ex "continue" \
  -ex "echo \n>>> the live kernel stopped inside __do_sys_getpid <<<\n" \
  -ex "backtrace" \
  -ex "info registers rip" \
  -ex "x/3i \$pc" \
  -ex "detach" \
  "$VMLINUX" >"$gdblog" 2>&1 || true

echo "=== gdb session ==="
cat "$gdblog"

# gdb labels the (aliased) getpid handler address __x64_sys_getpid; match either name.
grep -Eq "Breakpoint [0-9]+, .*sys_getpid" "$gdblog" \
  || die "gdb never hit the breakpoint on the getpid handler.
     See $gdblog and $work/qemu.log. (symbol present? nokaslr applied?)"
ok "gdb broke into the getpid syscall handler on the LIVE kernel — no rebuild"
if grep -q "do_syscall_64" "$gdblog"; then
  ok "backtrace shows the syscall path (… → do_syscall_64 → __do_sys_getpid)"
else
  warn "backtrace didn't show do_syscall_64 (non-fatal)"
fi
ok "lesson H1 complete"
