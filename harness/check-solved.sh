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
#   harness/check-solved.sh 05-the-driver-that-oopses  # just one
#
# Notes:
#   * Refuses to touch a lesson whose directory has uncommitted changes —
#     restoring is `git restore`, which would eat in-progress learner work.
#   * Runs each lesson's check.sh DIRECTLY (not via harness/check.sh), so no
#     pass-records are written: the dashboard never claims you solved a lesson
#     this script solved.
#   * C2 is skipped unless its KASAN kernel is built (opt-in, like the lesson).
#   * Lesson 01 edits the KERNEL TREE on the build volume, not repo files — it
#     needs apply-to-volume + incremental rebuild plumbing and is NOT covered yet.

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
  B2-trace-just-what-matters
  B4-events-and-histograms
  06-instrument-it-yourself
  05-the-driver-that-oopses
  07-char-device-with-ioctl
  C2-kasan-catches-you
)

ensure_kernel

run_one() {
  local d="$1" rc=0
  [ -f "$REPO_ROOT/$d/solution.patch" ] || die "no solution.patch in '$d'"
  [ -x "$REPO_ROOT/$d/check.sh" ]       || die "no executable check.sh in '$d'"

  if [ "$d" = C2-kasan-catches-you ] && [ ! -f "$KASAN_BZIMAGE" ]; then
    warn "skipping $d — its KASAN kernel isn't built (opt-in: make kasan-kernel)"
    return 0
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
