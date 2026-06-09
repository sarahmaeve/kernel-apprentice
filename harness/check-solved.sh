#!/usr/bin/env bash
# Verify CHALLENGE lessons are still SOLVABLE — the green half of their checks.
#
# Each CHALLENGE lesson ships red on main (the skeleton) and carries a committed
# solution.patch — the same code as its README's final graduated hint. Per
# lesson this script: applies the patch -> runs the lesson's own check.sh
# (expecting PASS) -> restores the committed skeleton. Run it whenever something
# load-bearing changes: a kernel pin bump, a tutorial.config edit, a harness
# refactor.
#
#   harness/check-solved.sh                            # sweep all solvable lessons
#   harness/check-solved.sh --no-kernel-edits          # skip kernel-tree lessons (01)
#   harness/check-solved.sh 05-the-driver-that-oopses  # just one
#
# Notes:
#   * Refuses to touch a lesson whose directory has uncommitted changes —
#     restoring is `git restore`, which would eat in-progress learner work.
#   * Runs each lesson's check.sh DIRECTLY (not via harness/check.sh), so no
#     pass-records are written: the dashboard never claims you solved a lesson
#     this script solved.
#   * C2 is skipped unless its KASAN kernel is built (opt-in, like the lesson).
#   * Lessons with a .reset-kernel manifest (01) edit the KERNEL TREE on the
#     build volume: their patch is applied to $KERNEL_SRC with patch(1), their
#     check does its own incremental rebuild, and restore re-extracts the
#     manifest files from the pinned tarball (same idiom as reset-volume.sh,
#     minus its pass-record side effects) + rebuilds the pristine bzImage.
#     That's two incremental kernel rebuilds — pass --no-kernel-edits (or
#     FAST=1 via make) to skip them.

set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
source "$HERE/lib.sh"
assert_in_container
need git

# The bind-mounted repo is owned by the host user; tell the container's git
# that's expected (ephemeral config inside the container, harmless).
git config --global --add safe.directory "$REPO_ROOT" 2>/dev/null || true

# CHALLENGE lessons with a committed solution.patch, in curriculum order.
SOLVABLE=(
  01-syscall-is-the-door
  B2-trace-just-what-matters
  B4-events-and-histograms
  06-instrument-it-yourself
  05-the-driver-that-oopses
  07-char-device-with-ioctl
  C2-kasan-catches-you
)

ensure_kernel

# Re-extract a .reset-kernel manifest's files from the pinned tarball, fresh
# mtime so kbuild recompiles them. Same idiom as reset-volume.sh, WITHOUT its
# pass-record clearing / status refresh (this script must not touch either).
restore_kernel_files() {
  local manifest="$1" f
  while IFS= read -r f; do
    case "$f" in ''|\#*) continue ;; esac
    tar -C "$BUILD_DIR" -xf "$CACHE_DIR/$KERNEL_TARBALL" "linux-${KERNEL_VERSION}/$f" \
      && touch "$KERNEL_SRC/$f" \
      && log "restored linux-${KERNEL_VERSION}/$f in the build volume"
  done < "$manifest"
}

# If we die between applying a kernel-tree solution and restoring it, put the
# source back on the way out (the bzImage may still carry the solution — say so).
KERNEL_TREE_DIRTY=""
trap 'if [ -n "$KERNEL_TREE_DIRTY" ]; then
        warn "interrupted mid-solve — restoring the kernel tree"
        restore_kernel_files "$KERNEL_TREE_DIRTY"
        warn "the built bzImage may still contain the solution; run make kernel (or any lesson-01 check) to rebuild"
      fi' EXIT

# Kernel-tree flavor: the lesson's solution edits $KERNEL_SRC, not repo files.
run_one_kernel() {
  local d="$1" rc=0 f
  local manifest="$REPO_ROOT/$d/.reset-kernel"
  local tarball="$CACHE_DIR/$KERNEL_TARBALL"
  need patch
  [ -f "$tarball" ] \
    || die "no $KERNEL_TARBALL in harness/.cache — restore re-extracts from it (run make kernel once)"

  # This lesson's learner work lives in the KERNEL TREE, where git can't see
  # it — compare the manifest files against the pristine tarball instead.
  while IFS= read -r f; do
    case "$f" in ''|\#*) continue ;; esac
    tar -xOf "$tarball" "linux-${KERNEL_VERSION}/$f" 2>/dev/null | cmp -s - "$KERNEL_SRC/$f" \
      || die "'$d': $f differs from the pristine $KERNEL_VERSION source — in-progress work?
     'make reset LESSON=$d' first (that wipes the kernel edit), then re-run."
  done < "$manifest"

  log "──────── solved-check: $d (kernel-tree edit — two incremental rebuilds) ────────"
  patch -p1 -d "$KERNEL_SRC" --no-backup-if-mismatch < "$REPO_ROOT/$d/solution.patch" \
    || die "solution.patch no longer applies to the $KERNEL_VERSION tree — skeleton and solution have drifted"
  KERNEL_TREE_DIRTY="$manifest"

  # The lesson's own check does the incremental rebuild that picks the edit up.
  ( cd "$REPO_ROOT/$d" && ./check.sh ) || rc=$?

  restore_kernel_files "$manifest"
  KERNEL_TREE_DIRTY=""
  log "rebuilding the pristine bzImage (incremental)"
  make -C "$KERNEL_SRC" ARCH="$GUEST_ARCH" -j"$(nproc)" bzImage >/dev/null \
    || warn "restore rebuild failed — run 'make kernel' before trusting lesson checks"

  if [ "$rc" -eq 0 ]; then
    ok "$d is solvable"
  else
    warn "$d FAILED while solved (rc=$rc) — the intended fix no longer passes its check"
  fi
  return "$rc"
}

run_one() {
  local d="$1" rc=0
  [ -f "$REPO_ROOT/$d/solution.patch" ] || die "no solution.patch in '$d'"
  [ -x "$REPO_ROOT/$d/check.sh" ]       || die "no executable check.sh in '$d'"

  if [ "$d" = C2-kasan-catches-you ] && [ ! -f "$KASAN_BZIMAGE" ]; then
    warn "skipping $d — its KASAN kernel isn't built (opt-in: make kasan-kernel)"
    return 0
  fi

  if [ -f "$REPO_ROOT/$d/.reset-kernel" ]; then
    if [ "$NO_KERNEL_EDITS" = 1 ]; then
      warn "skipping $d — kernel-tree lesson (--no-kernel-edits / FAST=1)"
      return 0
    fi
    run_one_kernel "$d"
    return $?
  fi

  # Modified TRACKED files are in-progress learner work; restoring would eat
  # them. (Untracked files are safe — git restore never touches those.)
  if [ -n "$(git -C "$REPO_ROOT" status --porcelain -uno -- "$d")" ]; then
    die "'$d' has uncommitted changes — commit/stash them or 'make reset LESSON=$d' first"
  fi

  log "──────── solved-check: $d ────────"
  git -C "$REPO_ROOT" apply "$REPO_ROOT/$d/solution.patch" \
    || die "solution.patch no longer applies in '$d' — skeleton and solution have drifted"
  ( cd "$REPO_ROOT/$d" && ./check.sh ) || rc=$?
  git -C "$REPO_ROOT" restore -- "$d"
  if [ "$rc" -eq 0 ]; then
    ok "$d is solvable"
  else
    warn "$d FAILED while solved (rc=$rc) — the intended fix no longer passes its check"
  fi
  return "$rc"
}

NO_KERNEL_EDITS=0
if [ "${1:-}" = "--no-kernel-edits" ]; then NO_KERNEL_EDITS=1; shift; fi

target="${1:-}"
if [ -n "$target" ]; then
  run_one "$target"
else
  fails=()
  for d in "${SOLVABLE[@]}"; do run_one "$d" || fails+=("$d"); done
  [ "${#fails[@]}" -eq 0 ] \
    || die "${#fails[@]} lesson(s) no longer solvable: ${fails[*]}"
  ok "ALL CHALLENGE lessons are still solvable"
fi
