#!/usr/bin/env bash
# Reset CHALLENGE lessons to their committed (unsolved) skeleton — lightweight, with
# no kernel/colima rebuild. The next `make check` recompiles the module incrementally.
#
# Safety: only reverts TRACKED files to HEAD. A solved lesson goes back to its
# committed skeleton; an uncommitted work-in-progress lesson (untracked) is never
# touched — so it's safe to prototype new lessons while resetting old ones.
#
#   harness/reset.sh         reset every lesson to its committed state
#   harness/reset.sh 06      reset one (short id or full dir name)

set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
cd "$ROOT"

restore() { git restore --source=HEAD --worktree -- "$@" 2>/dev/null || true; }

arg="${1:-}"
if [ -n "$arg" ]; then
  dir="$arg"
  [ -d "$dir" ] || dir="$(compgen -G "${arg}*" 2>/dev/null | head -n1 || true)"
  [ -n "$dir" ] && [ -d "$dir" ] || { echo "no lesson dir matches '$arg'" >&2; exit 1; }
  restore "$dir"
  echo "reset $dir to its committed skeleton"
else
  restore [0-9]*-*/ H[0-9]*-*/ wheel/
  echo "reset all lessons to their committed skeletons"
fi

echo "lightweight: the next 'make check' rebuilds the module incrementally (no full kernel/colima rebuild)."
echo "note: lesson 01's solution is a kernel edit in the build volume, not a repo file — ask for a volume reset if you want one."
