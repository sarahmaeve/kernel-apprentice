#!/usr/bin/env bash
# Build the OPTIONAL KASAN overlay kernel — a SECOND, separate kernel with
# CONFIG_KASAN on, used only by lesson C2. This is "build-a-KASAN-kernel": in real
# life you build a dedicated KASAN kernel to chase a memory-corruption bug, boot
# it, read the splat, then go back to your normal kernel. We mirror that exactly —
# the base tutorial kernel (harness/build-kernel.sh) is never touched.
#
# It extracts a SEPARATE copy of the pinned source and builds it IN-TREE under
# $KASAN_SRC on the build volume. (An out-of-tree O= build can't reuse the base
# tree, which is itself built in-tree — kbuild refuses an unclean source.) Cost: a
# second source extraction + a full second compile (minutes + extra disk). Entirely
# opt-in — nothing in the normal `make check` flow calls this; only
# `make kasan-kernel` and lesson C2's check do.

set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
source "$HERE/lib.sh"
assert_in_container
for t in make gcc tar sha256sum bc flex bison; do need "$t"; done

tarball="$CACHE_DIR/$KERNEL_TARBALL"

# The base build downloads + sha-verifies the tarball. If it isn't present, run it
# first — the KASAN kernel is an addition to the base workbench, not a replacement.
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

# 1. Extract a SEPARATE source tree (strip the linux-$VERSION/ prefix into KASAN_SRC).
if [ ! -d "$KASAN_SRC" ]; then
  log "extracting a second source tree -> $KASAN_SRC"
  mkdir -p "$KASAN_SRC"
  tar -C "$KASAN_SRC" --strip-components=1 -xf "$tarball"
fi

# 2. Configure in-tree: defconfig (once) + our base fragment + the KASAN fragment,
#    re-merged every run so config edits take effect (idempotent when unchanged).
log "configuring (defconfig + tutorial.config + config/kasan.config)"
( cd "$KASAN_SRC"
  [ -f .config ] || make ARCH="$GUEST_ARCH" defconfig
  scripts/kconfig/merge_config.sh -m .config \
      "$HARNESS_DIR/config/tutorial.config" "$HARNESS_DIR/config/kasan.config"
  make ARCH="$GUEST_ARCH" olddefconfig )

# Confirm KASAN survived olddefconfig (it can silently drop if a dep is missing) —
# fail loudly rather than ship a kernel that wouldn't catch anything.
grep -q '^CONFIG_KASAN=y' "$KASAN_SRC/.config" \
  || die "CONFIG_KASAN did not survive olddefconfig — check harness/config/kasan.config"

# 3. Build. bzImage = the bootable KASAN kernel; modules generates Module.symvers so
#    lesson C2's out-of-tree module links (and gets KASAN-instrumented).
njobs="$(nproc)"
log "building KASAN bzImage + modules -j$njobs (a SECOND kernel — this is the cost)"
make -C "$KASAN_SRC" ARCH="$GUEST_ARCH" -j"$njobs" bzImage
make -C "$KASAN_SRC" ARCH="$GUEST_ARCH" -j"$njobs" modules

[ -f "$KASAN_BZIMAGE" ] || die "build completed but KASAN bzImage missing at $KASAN_BZIMAGE"
ok "KASAN kernel ready: $KASAN_BZIMAGE ($(du -h "$KASAN_BZIMAGE" | cut -f1))"
