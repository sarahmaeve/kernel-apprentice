# kernel-apprentice

Training materials for learning to **read kernel code and debug software–kernel
interactions** — fast enough to be useful on real problems. Not a path to becoming
an upstream contributor; a path to localizing why *novel software* misbehaves on a
production-shaped box (blocked syscalls, resource limits, OOM, dropped packets).

The design and rationale live in **[DESIGN.md](DESIGN.md)**. This README is the
quickstart.

## How it works in one picture

> The **container is your workbench** (toolchain, tracing tools, QEMU). A **QEMU
> guest launched from it is the real, breakable kernel.** The safety boundary is
> QEMU, never the container.

Each lesson follows **Observe → Read → Touch**: a tool *shows* a phenomenon,
kernel C *explains* it, and your own `printk`/trace lets you *confirm the exact
line ran*. You drive; the symptom comes first.

## Prerequisites

- A container runtime: **Docker** or **Podman**. On macOS this project uses
  [colima](https://github.com/abiosoft/colima) (the Makefile starts it for you).
- `make` and `git` on the host.
- ~10 GB free disk for the kernel source tree + build.

Everything else (cross toolchain, QEMU, strace/perf/bpftrace/trace-cmd) ships
inside the workbench image — you don't install it on your host.

## Quickstart

```sh
# 1. Build the workbench image (starts colima on macOS automatically).
make image

# 2. Build the pinned kernel — the one-time slow step, then cached forever.
#    First run prints the tarball's sha256 and asks you to pin it (we don't guess
#    hashes); paste it into harness/versions.env and re-run. See harness/README.md.
make kernel

# 3. Do a lesson.
make check LESSON=01-syscall-is-the-door
```

`make help` lists every target. `make check` with no `LESSON` runs them all.

## Layout

```
DESIGN.md                     the design + rationale (read this)
Dockerfile                    the workbench image
Makefile                      host-side orchestration (colima + docker)
harness/                      shared machinery — build kernel, assemble guest, boot, grade
01-syscall-is-the-door/       lesson 1: find the function behind a syscall and prove it ran
02-printk-and-ring-buffer/    lesson 2: build a module, watch the kernel log ring buffer
wheel/works-on-my-laptop/     Wheel of Misfortune: a live, broken box to diagnose
```

Each lesson is a self-contained directory with a `README.md` (lesson + challenge +
graduated hints) and a `check.sh` that boots the guest and reports PASS/FAIL.

## Portability

This is meant to be cloned and explored by others, so it's built to be portable:

- **Runtime-agnostic:** `make RUNTIME=podman ...`; colima is used only where present.
- **Same guest everywhere:** the workbench and guest are pinned to `linux/amd64`
  (x86_64) on *every* host, so the `file:line` references in lessons are identical
  for all contributors. Native on Intel/x86 Linux; emulated-but-identical on Apple
  Silicon (slower first build, same behavior).
- **Pinned kernel:** `6.18.33` LTS (newest LTS; maintained to Dec 2028), set in
  `harness/versions.env`. Override there to re-pin.

## Status

Phase 1 vertical slice (DESIGN §9): the workbench, the harness, lessons 1–2, and
one Wheel scenario. See `DESIGN.md` for what comes next.
