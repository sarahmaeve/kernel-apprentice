#!/usr/bin/env bash
# Reset CHALLENGE lessons to their committed (unsolved) skeleton — lightweight, with
# no full kernel/colima rebuild. Handles BOTH kinds of "solve":
#   * repo edits   (module skeletons like 06) -> git-restore tracked files to HEAD
#   * volume edits (kernel-proper lessons like 01) -> re-extract the kernel files
#     listed in the lesson's .reset-kernel manifest from the pinned tarball
#
# Only reverts TRACKED repo files, so an uncommitted work-in-progress lesson
# (untracked) is never wiped — safe to prototype new lessons while resetting old ones.
#
#   harness/reset.sh         reset every lesson
#   harness/reset.sh 06      reset one (short id or full dir name)

set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
cd "$ROOT"

RUNTIME="${RUNTIME:-docker}"
PLATFORM="${PLATFORM:-linux/amd64}"
IMAGE="kernel-apprentice"
VOLUME="kernel-apprentice-build"

restore_repo() { git restore --source=HEAD --worktree -- "$@" 2>/dev/null || true; }

# Re-extract kernel files named in .reset-kernel manifests (in-container, since the
# kernel source lives in the build volume). Only spins a container if there's work.
volume_reset() {  # $1 = resolved lesson dir, or "" for all
  local has=""
  if [ -n "$1" ]; then
    [ -f "$1/.reset-kernel" ] && has=1
  else
    compgen -G "*/.reset-kernel" >/dev/null 2>&1 && has=1
  fi
  [ -n "$has" ] || return 0
  "$RUNTIME" run --rm --platform="$PLATFORM" \
    -v "$ROOT":/work -v "$VOLUME":/work/harness/.build "$IMAGE" \
    harness/reset-kernel.sh "$1"
}

arg="${1:-}"
if [ -n "$arg" ]; then
  dir="$arg"
  [ -d "$dir" ] || dir="$(compgen -G "${arg}*" 2>/dev/null | head -n1 || true)"
  [ -n "$dir" ] && [ -d "$dir" ] || { echo "no lesson dir matches '$arg'" >&2; exit 1; }
  restore_repo "$dir"
  echo "reset $dir (repo source) to its committed skeleton"
  volume_reset "$dir"
else
  restore_repo [0-9]*-*/ H[0-9]*-*/ wheel/
  echo "reset all lessons (repo source) to their committed skeletons"
  volume_reset ""
fi

echo "lightweight: the next 'make check' rebuilds the module (and any reset kernel file) incrementally."
