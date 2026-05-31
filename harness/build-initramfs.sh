#!/usr/bin/env bash
# Build the base BusyBox initramfs: a guest that boots straight to a shell, for
# poking around by hand. Lessons build their OWN initramfs (with a custom /init)
# via mk_initramfs; this one is just for exploration:
#
#   make initramfs            # build it
#   make shell                # then, inside the workbench:
#   harness/run-qemu.sh harness/.build/initramfs-base.cpio.gz

set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
source "$HERE/lib.sh"
# shellcheck source=initramfs.sh
source "$HERE/initramfs.sh"
assert_in_container

overlay="$(mktemp -d)"
cat > "$overlay/init" <<'INIT'
#!/bin/busybox sh
/bin/busybox mount -t proc     none /proc
/bin/busybox mount -t sysfs    none /sys
/bin/busybox mount -t devtmpfs none /dev 2>/dev/null
echo
echo "=== kernel-apprentice base guest (BusyBox) — kernel $(uname -r) ==="
echo "Type 'poweroff -f' to exit QEMU."
exec /bin/busybox sh
INIT
chmod +x "$overlay/init"

mkdir -p "$BUILD_DIR"
mk_initramfs "$INITRAMFS_BASE" "$overlay"
rm -rf "$overlay"
ok "base initramfs: $INITRAMFS_BASE"
