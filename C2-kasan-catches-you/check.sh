#!/usr/bin/env bash
# Lesson C2 check — "KASAN catches you" (OPTIONAL, CHALLENGE).
#
# REQUIRES THE KASAN OVERLAY KERNEL — a second, separate kernel build (opt-in; see
# harness/build-kasan-kernel.sh). Builds three tiny modules — each with one memory
# bug — and boots EACH IN ITS OWN GUEST so KASAN's first-report-then-quiet behavior
# can't mask a later bug and each is graded independently. Three escalating bugs:
#   part 1  kasan_oob  slab out-of-bounds write   (access + alloc stacks)
#   part 2  kasan_uaf  use-after-free             (adds the "Freed by task" stack)
#   part 3  kasan_df   double-free                (a different report category)
# Grades:
#   FAIL (and shows the splat) for any module whose bug still fires.
#   PASS once all three are fixed and KASAN stays silent for every one.

set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$HERE"; while [ ! -d "$ROOT/harness" ] && [ "$ROOT" != / ]; do ROOT="$(dirname "$ROOT")"; done
# shellcheck source=../harness/lib.sh
source "$ROOT/harness/lib.sh"
# shellcheck source=../harness/initramfs.sh
source "$ROOT/harness/initramfs.sh"
assert_in_container
need make; need gcc

MODS="kasan_oob kasan_uaf kasan_df"

warn "lesson C2 is OPTIONAL and runs on the KASAN overlay kernel — a SECOND full"
warn "kernel build (minutes + extra disk). Building it now if it isn't present..."
ensure_kasan_kernel

log "building the C2 modules against the KASAN kernel ($KASAN_SRC)"
make -C "$HERE/module" KDIR="$KASAN_SRC" >/dev/null
for m in $MODS; do
  [ -f "$HERE/module/$m.ko" ] || die "module build produced no $m.ko"
done

work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT

still_broken=""
for m in $MODS; do
  overlay="$work/ov_$m"; mkdir -p "$overlay"
  cp "$HERE/module/$m.ko" "$overlay/$m.ko"
  # Per-module init (un-quoted heredoc so $m expands here on the host).
  cat > "$overlay/init" <<INIT
#!/bin/busybox sh
busybox mount -t proc     none /proc
busybox mount -t sysfs    none /sys
busybox mount -t devtmpfs none /dev 2>/dev/null
echo "=== insmod $m.ko (KASAN is watching every access) ==="
insmod /$m.ko
echo "===== KASAN report for $m (only if its bug is still present) ====="
dmesg | busybox grep -A40 "BUG: KASAN"
echo "APPRENTICE-LOADED-$m"
busybox poweroff -f
INIT
  chmod +x "$overlay/init"

  img="$work/initramfs_$m.cpio.gz"
  mk_initramfs "$img" "$overlay"
  logf="$work/serial_$m.log"
  log "── booting guest for $m ──"
  KERNEL_IMAGE="$KASAN_BZIMAGE" "$ROOT/harness/run-qemu.sh" "$img" --timeout 90 --log "$logf"

  grep -q "APPRENTICE-LOADED-$m" "$logf" || die "$m.ko did not load cleanly (see $logf)"
  # Only this module is loaded in this guest, so ANY KASAN report here is its bug —
  # no need to scope by name (the faulting frame can be library code like string()).
  if grep -q "BUG: KASAN" "$logf"; then
    warn "[$m] KASAN reported its bug — still unfixed"
    still_broken="$still_broken $m"
  else
    ok "[$m] no KASAN report — clean"
  fi
done

if [ -n "$still_broken" ]; then
  warn "still failing:$still_broken — read each module's splat above:"
  warn "  * the first stack is the bad access — it points at the line in the .c"
  warn "  * 'Allocated by task' / 'Freed by task' show the object's history"
  warn "  * the shadow map marks which bytes were off-limits"
  die "diagnose each report and fix module/kasan_*.c so KASAN stays silent, then re-run."
fi

ok "no KASAN splat from any module — all three bugs fixed"
ok "lesson C2 complete — you read out-of-bounds, use-after-free, and double-free reports"
