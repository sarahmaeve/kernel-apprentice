#!/usr/bin/env bash
# harness/lib.sh — shared helpers sourced by every harness script and check.sh.
#
# Runs INSIDE the workbench container. Source it, don't execute it:
#     source "$(dirname "$0")/../harness/lib.sh"   # from a lesson's check.sh
#     source "$(dirname "$0")/lib.sh"              # from within harness/

set -euo pipefail

# --- Paths (independent of caller CWD) -----------------------------------
HARNESS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HARNESS_DIR/.." && pwd)"

# Build + download caches live under harness/ so they sit on the host bind-mount
# and persist across container/colima restarts (build once).
BUILD_DIR="${BUILD_DIR:-$HARNESS_DIR/.build}"
CACHE_DIR="${CACHE_DIR:-$HARNESS_DIR/.cache}"

# --- Pinned versions ------------------------------------------------------
# shellcheck source=versions.env
source "$HARNESS_DIR/versions.env"

KERNEL_SRC="$BUILD_DIR/linux-${KERNEL_VERSION}"
KERNEL_BZIMAGE="$KERNEL_SRC/arch/x86/boot/bzImage"
INITRAMFS_BASE="$BUILD_DIR/initramfs-base.cpio.gz"   # BusyBox-only base image

# --- Logging --------------------------------------------------------------
if [ -t 2 ]; then
  C_BLU=$'\033[34m'; C_GRN=$'\033[32m'; C_RED=$'\033[31m'
  C_YEL=$'\033[33m'; C_DIM=$'\033[2m';  C_OFF=$'\033[0m'
else
  C_BLU=''; C_GRN=''; C_RED=''; C_YEL=''; C_DIM=''; C_OFF=''
fi
log()  { printf '%s==>%s %s\n'  "$C_BLU" "$C_OFF" "$*" >&2; }
ok()   { printf '%sPASS%s %s\n' "$C_GRN" "$C_OFF" "$*" >&2; }
warn() { printf '%swarn%s %s\n' "$C_YEL" "$C_OFF" "$*" >&2; }
die()  { printf '%sFAIL%s %s\n' "$C_RED" "$C_OFF" "$*" >&2; exit 1; }

# Assert a tool exists, else fail with a hint to rebuild the image.
need() {
  command -v "$1" >/dev/null 2>&1 \
    || die "missing tool '$1' — is the workbench image current? (make image)"
}

# Guard: these scripts must run inside the container, not on the macOS host.
# (QEMU + the Linux toolchain only exist in the workbench.)
assert_in_container() {
  [ -f /.dockerenv ] || [ -n "${container:-}" ] || grep -qa docker /proc/1/cgroup 2>/dev/null \
    || warn "this looks like the host, not the workbench — run via 'make' or 'make shell'"
}

# Build the pinned kernel once if it isn't already present. Cheap no-op afterwards.
ensure_kernel() {
  [ -f "$KERNEL_BZIMAGE" ] || "$HARNESS_DIR/build-kernel.sh"
}
