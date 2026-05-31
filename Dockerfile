# syntax=docker/dockerfile:1
#
# The WORKBENCH (DESIGN.md §4): cross-toolchain + tracing tools + QEMU. This
# image is NOT the kernel under study. The real, breakable kernel is the QEMU
# guest this container launches — the safety boundary is QEMU, never the
# container (a container shares the host kernel and can't boot one you built).
#
# Runtime-agnostic by design (Docker/Podman/Colima). On this 2019 Intel Mac it
# runs under colima; QEMU inside has no KVM and runs emulated (TCG).

FROM debian:trixie-slim

ENV DEBIAN_FRONTEND=noninteractive

# One layer, no recommends, lists cleaned — keeps the image lean and reproducible.
RUN apt-get update && apt-get install -y --no-install-recommends \
      # --- kernel build toolchain ---
      build-essential bc bison flex \
      libssl-dev libelf-dev libncurses-dev \
      cpio xz-utils zstd kmod \
      # --- guest userspace for the lean initramfs (static, no libc needed) ---
      busybox-static \
      # --- the emulator: the real kernel runs here ---
      qemu-system-x86 \
      # --- observability / tracing tools (DESIGN.md §6 competency ladder) ---
      strace ltrace trace-cmd bpftrace gdb \
      # --- plumbing: downloads, source mgmt, initramfs assembly ---
      curl ca-certificates git gawk file rsync procps \
      # --- in-container editors (the kernel source lives in a Linux volume) ---
      nano vim \
    && rm -rf /var/lib/apt/lists/*

# The repo is bind-mounted here at run time (see Makefile: -v $PWD:/work). The
# kernel build lands in /work/harness/.build, so it persists on the host disk
# across container AND colima restarts (build once — see DESIGN.md notes).
WORKDIR /work

# We run QEMU emulated (TCG), so no /dev/kvm and no privilege juggling is needed;
# staying root keeps initramfs assembly (device nodes, ownership) simple.
CMD ["bash"]
