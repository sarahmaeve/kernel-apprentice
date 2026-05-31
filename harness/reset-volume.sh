#!/usr/bin/env bash
# In-container reset of a lesson's VOLUME-side state — invoked by harness/reset.sh
# (you don't call it directly). For the target lesson (or all):
#   1) clear its pass-record, so gen-status stops counting it as solved;
#   2) re-extract any kernel files it declares in .reset-kernel (undo a kernel solve);
#   3) refresh the live status.js so the dashboard reflects the reset.
# Needs the build volume + the download cache, so it runs inside the workbench.

set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
source "$HERE/lib.sh"
target="${1:-}"

checks="$BUILD_DIR/.checks"

# 1) Clear pass-record(s).
if [ -n "$target" ]; then
  rec="$checks/$(echo "$target" | tr / _).pass"
  [ -f "$rec" ] && rm -f "$rec" && echo "  cleared pass-record for $target" || true
else
  [ -d "$checks" ] && rm -f "$checks"/*.pass 2>/dev/null && echo "  cleared all pass-records" || true
fi

# 2) Re-extract kernel files named in .reset-kernel manifests, with a fresh mtime so
#    kbuild recompiles them (tar restores the old archive mtime otherwise).
tarball="$CACHE_DIR/$KERNEL_TARBALL"
if [ -f "$tarball" ] && [ -d "$KERNEL_SRC" ]; then
  manifests() {
    if [ -n "$target" ]; then
      [ -f "$REPO_ROOT/$target/.reset-kernel" ] && printf '%s\n' "$REPO_ROOT/$target/.reset-kernel"
    else
      for m in "$REPO_ROOT"/*/.reset-kernel; do [ -f "$m" ] && printf '%s\n' "$m"; done
    fi
  }
  while IFS= read -r manifest; do
    [ -n "$manifest" ] || continue
    while IFS= read -r f; do
      case "$f" in ''|\#*) continue ;; esac
      if tar -C "$BUILD_DIR" -xf "$tarball" "linux-${KERNEL_VERSION}/$f"; then
        touch "$BUILD_DIR/linux-${KERNEL_VERSION}/$f"
        echo "  restored linux-${KERNEL_VERSION}/$f in the build volume"
      fi
    done < "$manifest"
  done < <(manifests)
fi

# 3) Refresh the dashboard.
"$HERE/gen-status.sh" >/dev/null && echo "  refreshed status.js"
