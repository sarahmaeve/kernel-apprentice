#!/usr/bin/env bash
# Build the pinned tutorial kernel from source — the ONE-TIME slow step, cached in
# harness/.build/ so it survives container + colima restarts (DESIGN.md §4).
#
# Why source-build (not a prebuilt image): the lessons drop printk's into the
# kernel and build out-of-tree modules against this tree — both require a
# self-built, source-matched kernel. The compile is NATIVE in the container (not
# the emulated TCG path), so it's minutes, not hours.

set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
source "$HERE/lib.sh"
assert_in_container
for t in make gcc curl xz sha256sum bc flex bison; do need "$t"; done

mkdir -p "$BUILD_DIR" "$CACHE_DIR"
tarball="$CACHE_DIR/$KERNEL_TARBALL"

# 1. Download (cached across runs).
if [ ! -f "$tarball" ]; then
  log "downloading $KERNEL_URL"
  curl -fL --retry 3 --connect-timeout 30 -o "$tarball.partial" "$KERNEL_URL"
  mv "$tarball.partial" "$tarball"
fi

# 2. Verify the supply chain. We never guess hashes (see versions.env): if the pin
#    is blank, compute + print the real hash and stop so the user pins a real value.
actual="$(sha256sum "$tarball" | awk '{print $1}')"
if [ -z "${KERNEL_SHA256:-}" ]; then
  if [ "${ALLOW_UNPINNED:-0}" = "1" ]; then
    warn "KERNEL_SHA256 is blank — proceeding unpinned (ALLOW_UNPINNED=1)"
    warn "computed sha256 = $actual"
  else
    die "KERNEL_SHA256 is blank in harness/versions.env.
     Computed hash of the downloaded tarball:
         KERNEL_SHA256=\"$actual\"
     Paste that into versions.env and re-run (or pass ALLOW_UNPINNED=1 for a one-off)."
  fi
elif [ "$KERNEL_SHA256" != "$actual" ]; then
  die "sha256 MISMATCH for $KERNEL_TARBALL — refusing to build.
     pinned:   $KERNEL_SHA256
     computed: $actual"
else
  ok "tarball sha256 verified"
fi

# 3. Extract.
if [ ! -d "$KERNEL_SRC" ]; then
  log "extracting $KERNEL_TARBALL"
  tar -C "$BUILD_DIR" -xf "$tarball"
fi

# 4. Configure: x86_64 defconfig + our additive fragment. defconfig already boots
#    under QEMU; the fragment only adds what the lessons need → boots first try.
if [ ! -f "$KERNEL_SRC/.config" ]; then
  log "configuring (defconfig + harness/config/tutorial.config)"
  ( cd "$KERNEL_SRC"
    make ARCH="$GUEST_ARCH" defconfig
    scripts/kconfig/merge_config.sh -m .config "$HARNESS_DIR/config/tutorial.config"
    make ARCH="$GUEST_ARCH" olddefconfig )
fi

# 5. Build. bzImage = the bootable kernel; modules_prepare readies the tree so
#    lesson 02's out-of-tree module compiles against it (no full in-tree `make
#    modules`, which would needlessly build hundreds of defconfig drivers).
njobs="$(nproc)"
log "building bzImage -j$njobs (first build is the one-time cost; later edits are incremental)"
make -C "$KERNEL_SRC" ARCH="$GUEST_ARCH" -j"$njobs" bzImage
make -C "$KERNEL_SRC" ARCH="$GUEST_ARCH" -j"$njobs" modules_prepare

[ -f "$KERNEL_BZIMAGE" ] || die "build completed but bzImage missing at $KERNEL_BZIMAGE"
ok "kernel ready: $KERNEL_BZIMAGE ($(du -h "$KERNEL_BZIMAGE" | cut -f1))"
