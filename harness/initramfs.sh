#!/usr/bin/env bash
# harness/initramfs.sh — initramfs assembly helpers. SOURCE this, don't run it.
#
#   mk_initramfs OUT_CPIO_GZ OVERLAY_DIR [extra-guest-binary ...]
#   copy_with_libs BIN ROOT
#
# A lesson supplies an OVERLAY_DIR containing an executable /init (and any test
# binaries / .ko's); mk_initramfs combines it with a static BusyBox into a
# bootable gzipped cpio. Extra binaries (e.g. strace) are copied in with their
# shared libraries so they run inside the lean guest.

# Copy a dynamically-linked host binary + its shared libs + ELF loader into ROOT,
# preserving absolute paths.
copy_with_libs() {
  local bin path root
  bin="$1"; root="$2"
  path="$(command -v "$bin")" || die "guest binary not found in workbench: $bin"
  install -D "$path" "$root$path"
  ldd "$path" 2>/dev/null | awk '{ for (i=1;i<=NF;i++) if ($i ~ /^\//) print $i }' \
    | sort -u | while read -r lib; do install -D "$lib" "$root$lib"; done
}

# Build a gzipped cpio initramfs from a static BusyBox + an overlay dir (which must
# contain an executable /init) + optional extra guest binaries (with their libs).
mk_initramfs() {
  local out overlay root b applet
  out="$1"; overlay="$2"; shift 2
  need busybox; need cpio; need gzip
  [ -x "$overlay/init" ] || die "overlay '$overlay' must contain an executable /init"

  root="$(mktemp -d)"
  mkdir -p "$root"/{bin,sbin,proc,sys,dev,tmp,etc,root}

  # static BusyBox + one symlink per applet (sh, mount, cat, insmod, ...)
  install -D "$(command -v busybox)" "$root/bin/busybox"
  ( cd "$root/bin" && for applet in $(./busybox --list); do ln -sf busybox "$applet"; done )

  # extra guest tools (e.g. strace) plus their shared libraries
  for b in "$@"; do copy_with_libs "$b" "$root"; done

  # lesson payload (overlays /init + test programs / modules on top)
  cp -a "$overlay"/. "$root"/
  chmod +x "$root/init"

  ( cd "$root" && find . -print0 | cpio --null -o -H newc --quiet ) | gzip -9 > "$out"
  rm -rf "$root"
  log "initramfs: $out ($(du -h "$out" | cut -f1))"
}
