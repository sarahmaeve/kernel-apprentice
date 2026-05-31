#!/usr/bin/env bash
# Boot the pinned kernel + a given initramfs in QEMU, stream the serial console to
# the terminal, and capture it to a log. The guest is x86_64 for every contributor
# (lesson references match everywhere); acceleration is used only when the host can
# (KVM), otherwise emulation (TCG) — fine, the tutorial guest is tiny.
#
# Usage: run-qemu.sh INITRAMFS [--append STR] [--timeout SECS] [--log FILE]

set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
source "$HERE/lib.sh"
need qemu-system-x86_64; need timeout

initramfs="${1:?usage: run-qemu.sh INITRAMFS [--append STR] [--timeout SECS] [--log FILE]}"
shift
append=""
timeout_s="${QEMU_TIMEOUT:-120}"
logfile=""
while [ $# -gt 0 ]; do
  case "$1" in
    --append)  append="$2";   shift 2 ;;
    --timeout) timeout_s="$2"; shift 2 ;;
    --log)     logfile="$2";   shift 2 ;;
    *) die "unknown argument: $1" ;;
  esac
done

[ -f "$KERNEL_BZIMAGE" ] || die "no kernel at $KERNEL_BZIMAGE — run harness/build-kernel.sh first"
[ -f "$initramfs" ]      || die "no initramfs at $initramfs"
logfile="${logfile:-$(mktemp)}"

# Acceleration: KVM only when the container actually exposes /dev/kvm AND the arch
# matches; otherwise TCG. (On macOS/colima and Apple Silicon this is TCG by design.)
accel="tcg"
if [ -w /dev/kvm ] && [ "$(uname -m)" = "x86_64" ]; then accel="kvm"; fi
log "booting guest (accel=$accel, timeout=${timeout_s}s) — log: $logfile"

# panic=-1 + -no-reboot => the guest exits QEMU on a panic; a clean run ends when
# /init calls 'poweroff -f'. The host-side timeout guards against a hung guest.
set +e
timeout "${timeout_s}" qemu-system-x86_64 \
  -accel "$accel" -no-reboot -nographic \
  -m "${QEMU_MEM:-512M}" -smp "${QEMU_SMP:-2}" \
  -kernel "$KERNEL_BZIMAGE" \
  -initrd "$initramfs" \
  -append "console=ttyS0 panic=-1 ${append}" \
  < /dev/null 2>&1 | tee "$logfile"
rc=${PIPESTATUS[0]}
set -e

[ "$rc" = "124" ] && warn "QEMU hit the ${timeout_s}s timeout (guest may have hung)"
exit 0
