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
- ~10 GB free disk for the kernel build (kept in a Docker volume in the colima VM).

Everything else (cross toolchain, QEMU, strace/perf/bpftrace/trace-cmd) ships
inside the workbench image — you don't install it on your host.

## Quickstart

```sh
# 1. Build the workbench image (starts colima on macOS automatically).
make image

# 2. Build the pinned kernel — ONE-TIME, then cached. It runs in TWO steps:
#    2a. First run downloads 6.18.33, computes its sha256, and HALTS (expected) —
#        we never guess hashes. It prints:  KERNEL_SHA256="<64 hex chars>"
make kernel
#    2b. Paste that line into harness/versions.env (ideally after cross-checking it
#        against kernel.org), then re-run. It verifies the pin and compiles bzImage.
make kernel

# 3. Do a lesson.
make check LESSON=01-syscall-is-the-door
```

`make help` lists every target. `make check` with no `LESSON` runs them all.

> **Editing kernel source.** It lives in a Docker volume (see
> [harness/README.md](harness/README.md) for why), so edit it from inside
> `make shell` — `nano`/`vim` are installed, or attach your IDE to the running
> container. The lesson files in this repo are edited normally on your host.

## Layout

```
DESIGN.md                     the design + rationale (read this)
POTENTIAL-CURRICULUM.md       the module map + build order (what exists, what's next)
Dockerfile                    the workbench image
Makefile                      host-side orchestration (colima + docker)
harness/                      shared machinery — build kernel, assemble guest, boot, grade
01-syscall-is-the-door/       lesson 1: find the function behind a syscall and prove it ran
02-printk-and-ring-buffer/    lesson 2: build a module, watch the kernel log ring buffer
...                           one directory per lesson — see the curriculum map for the rest
wheel/                        Wheel of Misfortune: live, broken boxes to diagnose
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
- **Build isolation:** the kernel builds on a Linux-native Docker volume, sidestepping
  host-filesystem quirks (macOS symlink/case-insensitivity limits).

## Status

Well past the Phase 1 vertical slice (DESIGN §9): **15 lessons and three Wheel
scenarios** are built across modules A (the boundary), B (the full tracing
track), C (memory), E (oops anatomy + the oops-fix), G (the modification
capstone) and H (live-kernel gdb). The module map, build order, and what comes
next live in [POTENTIAL-CURRICULUM.md](POTENTIAL-CURRICULUM.md).
