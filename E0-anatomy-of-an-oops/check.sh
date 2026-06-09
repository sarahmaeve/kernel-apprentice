#!/usr/bin/env bash
# Lesson E0 check — "Anatomy of an oops" (READY).
#
# Builds the specimen module, boots a guest that triggers a WARN, a BUG() and a
# NULL-deref oops (the fatal two in child processes, so init survives), then
# decodes the oops RIP back to file:line with the kernel tree's scripts/faddr2line.
# Grades (READY, green out of the box): PASS iff all three report shapes appear,
# the RIP names e0_write, the decode lands in e0_anatomy.c, and taint shows W.

set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$HERE"; while [ ! -d "$ROOT/harness" ] && [ "$ROOT" != / ]; do ROOT="$(dirname "$ROOT")"; done
# shellcheck source=../harness/lib.sh
source "$ROOT/harness/lib.sh"
# shellcheck source=../harness/initramfs.sh
source "$ROOT/harness/initramfs.sh"
assert_in_container
need make

ensure_kernel

log "building e0_anatomy.ko against $KERNEL_SRC"
make -C "$HERE/module" KDIR="$KERNEL_SRC" >/dev/null
ko="$HERE/module/e0_anatomy.ko"
[ -f "$ko" ] || die "module build produced no e0_anatomy.ko"

work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
overlay="$work/overlay"; mkdir -p "$overlay"
cp "$ko" "$overlay/e0_anatomy.ko"
cat > "$overlay/init" <<'INIT'
#!/bin/busybox sh
busybox mount -t proc     none /proc
busybox mount -t sysfs    none /sys
busybox mount -t devtmpfs none /dev 2>/dev/null
echo "=== insmod e0_anatomy.ko (an out-of-tree module — taints with O) ==="
insmod /e0_anatomy.ko
echo "taint bitmask: $(busybox cat /proc/sys/kernel/tainted)"
echo
echo "=== 1/3 WARN — a loud complaint, not a crash ==="
busybox sh -c 'echo warn > /proc/ka-anatomy'
echo "(writer returned $? — execution continued past the WARN)"
echo "taint bitmask: $(busybox cat /proc/sys/kernel/tainted)"
echo
echo "=== 2/3 BUG() — an explicit, fatal assertion ==="
busybox sh -c 'echo bug > /proc/ka-anatomy'
echo "(writer returned $? — killed; the kernel survives)"
echo "taint bitmask: $(busybox cat /proc/sys/kernel/tainted)"
echo
echo "=== 3/3 NULL deref — a page fault the kernel never expected ==="
busybox sh -c 'echo oops > /proc/ka-anatomy'
echo "(writer returned $? — killed; the kernel survives)"
echo "taint bitmask: $(busybox cat /proc/sys/kernel/tainted)"
echo
echo "===== THE THREE REPORTS (dmesg) ====="
dmesg | busybox tail -n 100
echo "APPRENTICE-DONE"
busybox poweroff -f
INIT
chmod +x "$overlay/init"

img="$work/initramfs.cpio.gz"
mk_initramfs "$img" "$overlay"

logf="$work/serial.log"
"$ROOT/harness/run-qemu.sh" "$img" --timeout 90 --log "$logf"

grep -qE "WARNING:.*e0_write" "$logf" \
  || die "no WARNING from e0_write — did 'echo warn' reach /proc/ka-anatomy? (see $logf)"
ok "shape 1/3 — WARN: complaint with a full backtrace; execution continued"

grep -q "kernel BUG at" "$logf" \
  || die "no 'kernel BUG at ...' line — the BUG() report is missing (see $logf)"
grep -q "invalid opcode" "$logf" \
  || die "BUG() fired but no 'invalid opcode' line — that's the ud2 trap BUG() compiles to (see $logf)"
ok "shape 2/3 — BUG(): assertion names its file:line; the writer was killed"

grep -q "BUG: kernel NULL pointer dereference" "$logf" \
  || die "no NULL-deref oops in the log (see $logf)"
grep -qE "RIP: 0010:e0_write(\.[a-z0-9._]+)?\+" "$logf" \
  || die "oops present but no RIP naming e0_write (see $logf)"
ok "shape 3/3 — oops: unexpected page fault; RIP names e0_write (its .cold half)"

# The Touch step, automated: decode the oops RIP — the one inside the NULL-deref
# report (gcc parks the unlikely failure path in e0_write.cold) — to a source
# line, exactly as the README walks by hand from `make shell`.
rip="$(grep -A12 "BUG: kernel NULL pointer dereference" "$logf" \
         | grep -m1 -oE 'e0_write[a-z0-9._]*\+0x[0-9a-f]+/0x[0-9a-f]+' || true)"
[ -n "$rip" ] || die "could not extract the oops RIP (func+offset/size) from its report"
# For module symbols the oops's /size is the kernel's gap-to-next-symbol estimate
# and can disagree with the .ko's recorded ELF size, making faddr2line refuse with
# "size mismatch" — so decode with func+offset only (the README teaches the same).
decoded="$("$KERNEL_SRC/scripts/faddr2line" "$ko" "${rip%/*}" 2>&1 || true)"
printf '%s\n' "$decoded" >&2
grep -q "e0_anatomy.c" <<<"$decoded" \
  || die "faddr2line did not resolve $rip into e0_anatomy.c — was the module built with -g?"
ok "decoded: $rip -> $(grep -oE 'e0_anatomy\.c:[0-9]+' <<<"$decoded" | head -n 1) — the faulting store (faddr2line)"

grep -qE "Tainted:.*W" "$logf" \
  || die "no 'Tainted: ... W' in the later reports — the WARN should have tainted the kernel (see $logf)"
ok "taint trail present — W (warned) joined O (out-of-tree); D follows the first die"
ok "lesson E0 complete — you can read every line of an oops"
