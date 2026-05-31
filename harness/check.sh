#!/usr/bin/env bash
# Run one lesson's check, or all of them in curriculum order. Ensures the kernel is
# built first (the one-time cost), then dispatches to each lesson's own check.sh.
#
#   harness/check.sh                          # run every lesson in order
#   harness/check.sh 01-syscall-is-the-door   # run just one

set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=lib.sh
source "$HERE/lib.sh"
assert_in_container

# Curriculum order. The Wheel scenario is included as part of the Phase 1 slice.
LESSONS=(
  01-syscall-is-the-door
  02-printk-and-ring-buffer
  wheel/works-on-my-laptop
)

ensure_kernel

run_one() {
  local d="$1" rec
  [ -x "$REPO_ROOT/$d/check.sh" ] || die "no executable check.sh in '$d'"
  # Pass-record consumed by harness/gen-status.sh. Clear first, write only on
  # success (set -e aborts before the write if the check fails) — so the dashboard
  # never shows a stale green.
  rec="$BUILD_DIR/.checks/$(echo "$d" | tr / _).pass"
  mkdir -p "$BUILD_DIR/.checks"; rm -f "$rec"
  log "──────── checking: $d ────────"
  ( cd "$REPO_ROOT/$d" && ./check.sh )
  : > "$rec"
  ok "$d"
}

target="${1:-}"
if [ -n "$target" ]; then
  run_one "$target"
else
  for d in "${LESSONS[@]}"; do run_one "$d"; done
  ok "ALL lesson checks passed"
fi
