# harness/ — the shared workbench machinery

Everything here runs **inside the workbench container** and is driven from the host
by the top-level `Makefile`. Nothing here is a lesson; it's the plumbing every
lesson reuses: build the kernel once, assemble a guest, boot it in QEMU, capture
the serial console, grade the result.

## The one distinction that matters

> The **container is the workbench**. The **QEMU guest is the real, breakable
> kernel.** The safety boundary is QEMU, never the container.

See `DESIGN.md` §4. A container shares the host kernel and can't boot one you
built; the QEMU guest runs the kernel you compiled here and can be broken freely.

## Files

| File | Role |
|---|---|
| `versions.env` | The single source of truth for pins (kernel `6.18.33` LTS, guest arch). |
| `config/tutorial.config` | Kconfig fragment merged onto `defconfig` — adds only what lessons need. |
| `lib.sh` | Shared paths + logging + `need`/`ensure_kernel` helpers. **Sourced**, not run. |
| `initramfs.sh` | `mk_initramfs` / `copy_with_libs` — assemble a guest from BusyBox + an overlay. **Sourced.** |
| `build-kernel.sh` | Download (verified) → configure → build `bzImage`. The one-time slow step. |
| `build-initramfs.sh` | Build a base BusyBox guest that boots to a shell (for poking around). |
| `run-qemu.sh` | Boot `bzImage` + an initramfs, stream + capture serial, enforce a timeout. |
| `check.sh` | Dispatcher: run one lesson's `check.sh`, or all in order. |

## Build once, reuse forever

The kernel source tree and `bzImage` live in `harness/.build/` (gitignored), which
is **bind-mounted from the host**. So the slow full compile happens exactly once
and survives `colima stop/start` and container removal. After that, editing one
`.c` is an **incremental** rebuild — seconds. The compile is *native* in the
container (only the guest *runs* emulated), so it's minutes, not hours.

## Portability (a project goal)

- **Runtime-agnostic:** `make RUNTIME=podman ...` works; colima is used only where
  present (macOS). Linux hosts skip it.
- **Same guest for everyone:** the workbench image and the guest are pinned to
  `linux/amd64` / x86_64 on *every* host, so the `file:line` references in lesson
  READMEs are identical for all contributors. Native on Intel/x86 Linux;
  emulated-but-identical on Apple Silicon.
- **KVM when available:** `run-qemu.sh` uses KVM only if the container exposes
  `/dev/kvm`; otherwise TCG. Either way the guest behaves the same.

## First-build supply chain

`versions.env` ships with `KERNEL_SHA256` **blank on purpose** — we don't guess
hashes. On the first `make kernel`, `build-kernel.sh` downloads the tarball,
computes the real hash, prints it, and refuses to build until you paste it into
`versions.env` (or pass `ALLOW_UNPINNED=1` for a one-off). Pin it once and the
supply chain is locked for everyone.
