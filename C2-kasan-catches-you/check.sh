#!/usr/bin/env bash
# Lesson C2 check — "KASAN catches you" (OPTIONAL, CHALLENGE).
#
# REQUIRES THE KASAN OVERLAY KERNEL — a second, separate kernel build (opt-in; see
# harness/build-kasan-kernel.sh). Builds kasan_demo.ko against that kernel, boots
# the KASAN guest, loads the module, and captures the console. Grades:
#   FAIL (and shows the splat) while the off-by-one bug is present — KASAN reports
#        slab-out-of-bounds the instant the module writes past its buffer.
#   PASS once you fix the loop bound so KASAN stays silent and the module loads.

set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$HERE"; while [ ! -d "$ROOT/harness" ] && [ "$ROOT" != / ]; do ROOT="$(dirname "$ROOT")"; done
# shellcheck source=../harness/lib.sh
source "$ROOT/harness/lib.sh"
# shellcheck source=../harness/initramfs.sh
source "$ROOT/harness/initramfs.sh"
assert_in_container
need make; need gcc

warn "lesson C2 is OPTIONAL and runs on the KASAN overlay kernel — a SECOND full"
warn "kernel build (minutes + extra disk). Building it now if it isn't present..."
ensure_kasan_kernel

log "building kasan_demo.ko against the KASAN kernel ($KASAN_SRC)"
make -C "$HERE/module" KDIR="$KASAN_SRC" >/dev/null
ko="$HERE/module/kasan_demo.ko"
[ -f "$ko" ] || die "module build produced no kasan_demo.ko"

work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
overlay="$work/overlay"; mkdir -p "$overlay"
cp "$ko" "$overlay/kasan_demo.ko"
cat > "$overlay/init" <<'INIT'
#!/bin/busybox sh
busybox mount -t proc     none /proc
busybox mount -t sysfs    none /sys
busybox mount -t devtmpfs none /dev 2>/dev/null
echo "=== insmod kasan_demo.ko (KASAN is watching every access) ==="
insmod /kasan_demo.ko
echo "=== KASAN report (only appears if the module touched memory it shouldn't) ==="
dmesg | busybox grep -A40 "BUG: KASAN" | busybox head -n 60
rmmod kasan_demo 2>/dev/null
echo "APPRENTICE-DONE"
busybox poweroff -f
INIT
chmod +x "$overlay/init"

img="$work/initramfs.cpio.gz"
mk_initramfs "$img" "$overlay"

logf="$work/serial.log"
KERNEL_IMAGE="$KASAN_BZIMAGE" "$ROOT/harness/run-qemu.sh" "$img" --timeout 120 --log "$logf"

grep -q "kasan_demo: filling" "$logf" || die "module did not load (see $logf)"

# RED only on a KASAN report tied to OUR module (the splat names kasan_demo on its
# first line + stack) — so an unrelated boot-time splat can't skew the verdict.
if grep -A30 "BUG: KASAN" "$logf" | grep -q "kasan_demo"; then
  warn "KASAN caught a memory bug in kasan_demo.ko — read the splat above:"
  warn "  * the first stack is the BAD ACCESS — that's the line to fix"
  warn "  * 'Allocated by task' is the kmalloc that owns the memory"
  warn "  * the shadow map marks the redzone (fc) you wrote into"
  die "fix the off-by-one loop bound in module/kasan_demo.c so the write stays in bounds, then re-run."
fi

ok "no KASAN splat — your fix keeps every access in bounds"
ok "lesson C2 complete — you read a KASAN report and fixed the bug it found"
