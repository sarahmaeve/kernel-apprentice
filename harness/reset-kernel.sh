#!/usr/bin/env bash
# Undo a kernel-proper "solve" by re-extracting the lesson's kernel files (named in
# its .reset-kernel manifest) from the pinned tarball into the build volume.
#
# Runs IN-CONTAINER (the kernel source lives in the build volume; the tarball is in
# the host-mounted cache). Invoked by harness/reset.sh — you don't call it directly.
#   harness/reset-kernel.sh                          all lessons with a manifest
#   harness/reset-kernel.sh 01-syscall-is-the-door   one lesson

set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
source "$HERE/lib.sh"
target="${1:-}"

tarball="$CACHE_DIR/$KERNEL_TARBALL"
[ -f "$tarball" ]    || { echo "no download cache ($tarball) — nothing to reset"; exit 0; }
[ -d "$KERNEL_SRC" ] || { echo "no extracted kernel tree — nothing to reset"; exit 0; }

list_manifests() {
  if [ -n "$target" ]; then
    [ -f "$REPO_ROOT/$target/.reset-kernel" ] && printf '%s\n' "$REPO_ROOT/$target/.reset-kernel"
  else
    for m in "$REPO_ROOT"/*/.reset-kernel; do [ -f "$m" ] && printf '%s\n' "$m"; done
  fi
}

n=0
while IFS= read -r manifest; do
  [ -n "$manifest" ] || continue
  while IFS= read -r f; do
    case "$f" in ''|\#*) continue ;; esac
    if tar -C "$BUILD_DIR" -xf "$tarball" "linux-${KERNEL_VERSION}/$f"; then
      # tar restores the archive's (old) mtime; bump it to now so kbuild recompiles
      # the file instead of trusting the stale object that still has the solution.
      touch "$BUILD_DIR/linux-${KERNEL_VERSION}/$f"
      echo "  restored linux-${KERNEL_VERSION}/$f in the build volume"
      n=$((n + 1))
    fi
  done < "$manifest"
done < <(list_manifests)

if [ "$n" -gt 0 ]; then
  echo "restored $n kernel file(s); the next 'make check' rebuilds them incrementally."
else
  echo "no kernel-edit lessons to reset."
fi
