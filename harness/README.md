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

## Build once, reuse forever — on a Linux-native volume

The kernel source tree and `bzImage` live in `harness/.build/`, which is a **Docker
named volume** (`kernel-apprentice-build`), **not** the host bind mount.

Why a volume: the kernel tree is full of relative symlinks (e.g.
`tools/testing/selftests/bpf/disasm.c -> ../../../../kernel/bpf/disasm.c`). On
macOS the repo reaches the container over a virtiofs bind mount, and `tar` **cannot
create those symlinks there** — it fails with `EACCES`, and the half-made links even
resist `rm`. The identical tarball extracts cleanly on a Linux ext4 volume, so
that's where the build lives. (This also sidesteps macOS case-insensitivity.)

The volume persists across `colima stop/start` and container removal, so the slow
full compile happens exactly once; `make clean` removes it. The compile is *native*
in the container (only the guest *runs* emulated), so it's minutes, not hours. Only
the download (`harness/.cache/`, a plain file virtiofs handles fine) stays on the
host bind mount, so re-creating the volume never re-downloads.

### Editing the kernel source

Because the source lives in the volume, edit it from inside the workbench:

```sh
make shell
nano harness/.build/linux-6.18.33/kernel/sys.c   # or vim — both are installed
```

VS Code / Cursor users can **Attach to Running Container** for a full IDE on the
volume. `make check` (run from the host) starts a fresh container on the same
volume, so it always sees your edits.

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
