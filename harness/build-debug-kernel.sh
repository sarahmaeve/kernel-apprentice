#!/usr/bin/env bash
# Build the DEBUG overlay kernel — a SECOND, separate kernel with lockdep
# (CONFIG_PROVE_LOCKING) and KCSAN on, used by Module D's lessons D1 and D2. This
# is "build-a-debug-kernel": in real life you build a dedicated kernel with the
# lock prover / concurrency sanitizer to chase a deadlock or a data race, boot it,
# read the splat, then go back to your normal kernel. We mirror that exactly — the
# base tutorial kernel (harness/build-kernel.sh) is never touched.
#
# Like the KASAN overlay (build-kasan-kernel.sh), it extracts a SEPARATE copy of
# the pinned source and builds it IN-TREE under $DEBUG_SRC on the build volume.
# Cost: a second source extraction + a full second compile (minutes + extra disk).
# Nothing in the normal `make check` flow calls this; `make debug-kernel` and
# Module D's D1/D2 checks tell you when you need it.

set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
source "$HERE/lib.sh"
assert_in_container
for t in make gcc tar sha256sum bc flex bison; do need "$t"; done

tarball="$CACHE_DIR/$KERNEL_TARBALL"

# The base build downloads + sha-verifies the tarball. If it isn't present, run it
# first — the debug kernel is an addition to the base workbench, not a replacement.
if [ ! -f "$tarball" ]; then
  log "kernel tarball not present — running the base build first to fetch + verify it"
  "$HERE/build-kernel.sh"
fi

# Re-verify the cached tarball before extracting a second tree — never trust a
# download blindly (see versions.env).
if [ -n "${KERNEL_SHA256:-}" ]; then
  actual="$(sha256sum "$tarball" | awk '{print $1}')"
  [ "$KERNEL_SHA256" = "$actual" ] || die "sha256 MISMATCH for cached $KERNEL_TARBALL — refusing to build.
     pinned:   $KERNEL_SHA256
     computed: $actual"
fi

# 1. Extract a SEPARATE source tree (strip the linux-$VERSION/ prefix into DEBUG_SRC).
if [ ! -d "$DEBUG_SRC" ]; then
  log "extracting a second source tree -> $DEBUG_SRC"
  mkdir -p "$DEBUG_SRC"
  tar -C "$DEBUG_SRC" --strip-components=1 -xf "$tarball"
fi

# 2. Configure in-tree: defconfig (once) + our base fragment + the debug fragment,
#    re-merged every run so config edits take effect (idempotent when unchanged).
log "configuring (defconfig + tutorial.config + config/debug.config)"
( cd "$DEBUG_SRC"
  [ -f .config ] || make ARCH="$GUEST_ARCH" defconfig
  scripts/kconfig/merge_config.sh -m .config \
      "$HARNESS_DIR/config/tutorial.config" "$HARNESS_DIR/config/debug.config"
  make ARCH="$GUEST_ARCH" olddefconfig )

# Confirm both survived olddefconfig (they can silently drop if a dep is missing) —
# fail loudly rather than ship a kernel that wouldn't catch anything.
grep -q '^CONFIG_PROVE_LOCKING=y' "$DEBUG_SRC/.config" \
  || die "CONFIG_PROVE_LOCKING did not survive olddefconfig — check harness/config/debug.config"
grep -q '^CONFIG_KCSAN=y' "$DEBUG_SRC/.config" \
  || die "CONFIG_KCSAN did not survive olddefconfig — KCSAN needs compiler support (gcc 11+); check harness/config/debug.config"

# 3. Build. bzImage = the bootable debug kernel; modules generates Module.symvers so
#    D1/D2's out-of-tree modules link (and get lockdep/KCSAN-instrumented).
njobs="$(nproc)"
log "building DEBUG bzImage + modules -j$njobs (a SECOND kernel — this is the cost)"
make -C "$DEBUG_SRC" ARCH="$GUEST_ARCH" -j"$njobs" bzImage
make -C "$DEBUG_SRC" ARCH="$GUEST_ARCH" -j"$njobs" modules

[ -f "$DEBUG_BZIMAGE" ] || die "build completed but debug bzImage missing at $DEBUG_BZIMAGE"
ok "debug kernel ready: $DEBUG_BZIMAGE ($(du -h "$DEBUG_BZIMAGE" | cut -f1))"
