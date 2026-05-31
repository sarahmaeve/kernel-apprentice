# DESIGN.md — Kernel Debugging Apprenticeship

*Working title. This document captures the design as it stands after the initial
design conversation. It is the first concrete artifact for the project — the
"first step" — and is meant to be argued with and revised, not treated as fixed.*

---

## 1. North Star

Teach someone already comfortable with Linux and programming to **read kernel code
and debug how software interacts with the kernel** — fast enough to be useful on
real problems.

The motivating scenario is concrete: people increasingly look at kernel code to
debug low-level, on-prem interactions between *novel software* and the system —
a new service, runtime, driver, or appliance that behaves badly in a
production-shaped environment in ways that don't show up on a developer laptop.

### What this project is

- Debugging **software–kernel interactions** and software-development-adjacent
  problems: blocked syscalls, resource limits, OOM, contention, a misbehaving
  out-of-tree module, packets quietly dropped in the stack.
- Building the **reader + tracer** skill set: fluency at the syscall boundary,
  enough of a subsystem map to localize a problem, real facility with
  observability tooling, and the ability to read kernel C and a stack trace.

### What this project is deliberately *not*

- Not a path to becoming a kernel contributor who lands upstream patches.
- Not focused on deep, rare, or exotic kernel-internals bugs.
- Modification of the kernel is a **confirmation tool used late**, not the goal.

This scoping is intentional and load-bearing. Scenarios are chosen because they
look like everyday software/operational reality, not because they exercise
obscure corners of the kernel.

---

## 2. Audience & Prerequisites

- Comfortable with Linux as a user and with general programming.
- Not currently doing kernel work; no prior kernel-internals knowledge assumed.
- Able to read C well enough to follow a function (idioms taught as they appear).

---

## 3. Pedagogical Principles

**Observe → Read → Touch ("one event, three views").**
Each lesson anchors on a single observable moment and walks it through three
lenses: a tool *shows* the phenomenon, a code snippet *explains* the machinery,
and the learner's own `printk` (or a kprobe) lets them *reach in* and confirm
"that exact line ran." Abstract kernel concepts become concrete fastest when the
same event is seen three ways rather than three things seen once.

**Symptom-first.**
The learner is handed the symptom as production would present it — a hang, a
metric, an oops in the log — and is *not* told what's wrong. They drive.

**The feedback loop is the product.**
Edit → build → boot → observe must be fast and safe. Slow full-distro builds and
real-hardware reboots kill momentum. A tiny config + small boot image + a
one-command runner keeps iterations to seconds.

**Verification is the game.**
Each lesson and scenario has an automated check: boot the target, inspect the
output (a marker in dmesg, a `/proc` value, a userspace test's exit code), report
PASS/FAIL. For diagnosis scenarios, the win condition is *pointing at the
evidence*, not naming the cause.

---

## 4. Environment Architecture

The single most important distinction:

> **The container is the workbench. A QEMU VM launched from it is the real,
> breakable kernel.** The safety boundary for kernel experiments is QEMU — not
> the container.

A container shares the host's kernel; it cannot boot a kernel you built, and
loading a module in one either fails or touches the *host* kernel. So the
container's job is a reproducible, disposable **workbench**: pinned kernel
source, build toolchain, tracing tools, and QEMU itself. The QEMU **guest** is
the kernel the learner observes, modifies, and breaks freely.

### Components

- **Workbench container** — built from a `Dockerfile` / devcontainer. Holds the
  cross-toolchain, a *pinned* kernel source tree, tracing tools (strace, perf,
  bpftrace, ftrace/trace-cmd), and QEMU. Runtime-agnostic: Docker, Podman, or
  Colima.
- **QEMU guest** — the target kernel. Built in the container, booted in QEMU with
  serial console captured for verification.
  - **Lean initramfs (BusyBox)** for fast printk/observability drills — boots in
    seconds.
  - **Fuller rootfs (small Debian/Alpine disk image)** for scenarios that run a
    realistic software stack — slower, reserved for those lessons.
- **Baby stacks** — scaled-down, production-shaped software (a database, a queue,
  a service) authored as container images, then *exported into guest disk images*
  so they stay defined as reproducible code. Run them in the container for
  cheap boundary observation early; run them in the guest when you need to read
  and modify the kernel they exercise.

### Why the guest, not the container, for real kernel work

- Source-matched reading: the guest runs the kernel whose source is on the bench.
- Modification: `printk`, custom modules, rebuilds — only possible on a kernel
  you control.
- Production fidelity: the guest kernel version and config can be **pinned to
  match a production kernel**; the container is stuck with whatever its host VM
  ships.

### macOS notes (Intel, ~2019 hardware)

- A 2019 Mac is Intel/x86-64 — the path of least resistance for kernel work; no
  cross-architecture friction.
- The container runtime on macOS already runs inside a Linux VM. QEMU launched
  there has **no KVM acceleration** and runs emulated (TCG). A stripped-down
  tutorial kernel still boots in seconds; heavier baby-stack guests are slower.
- Pin the kernel source version. Internal APIs and line numbers churn between
  releases; unpinned source makes lesson references rot.

---

## 5. Repository Layout

A git repo of directories, each level self-contained and verifiable.

```
.
├── DESIGN.md
├── Dockerfile              # the workbench image
├── harness/                # shared QEMU runner, rootfs/initramfs builders, build helpers
├── 01-syscall-is-the-door/
│   ├── README.md           # lesson + challenge + graduated hints
│   ├── check.sh            # runs in-container, boots QEMU, verifies outcome
│   └── ...                 # starter files
├── 02-printk-and-ring-buffer/
├── 03-proc-is-code/
├── 04-kernel-narrates-itself/
└── wheel/                  # incident scenarios (see §7)
```

- Solutions live on a separate branch so they can't be peeked at by accident.
- `make check` runs the current level's `check.sh`.

---

## 6. Competency Ladder (what lessons build toward)

1. **The boundary** — syscalls, file descriptors, signals, mmap, `ioctl`, and the
   `/proc` / `/sys` / `debugfs` surfaces. Most novel-software interactions live here.
2. **A subsystem map** — enough structure to localize: scheduling vs. memory vs.
   block I/O vs. network vs. interrupts vs. locking.
3. **Observability fluency (the core skill)** — strace at the boundary; perf,
   ftrace, and eBPF/bpftrace inside. Dynamic tracing inspects a live kernel
   without rebuilding — essential when you can't reproduce in a clean lab.
4. **Reading kernel C under pressure** — following a path from a stack trace or
   tracepoint into source; recognizing idioms (goto error handling, refcounting,
   locks, RCU conceptually); reading an oops.
5. **Crash analysis** — `crash` on a kdump vmcore, KASAN/lockdep reports.
6. **Modification (occasional)** — a printk or tracepoint to confirm a hypothesis;
   a patch to test a fix. Used after tracing has localized the problem.

### First lessons (the apprentice arc)

Each follows Observe → Read → Touch, mystery-first where possible.

1. **The syscall is the door** — `strace cat /etc/hostname` → read a
   `SYSCALL_DEFINE` → drop a printk in that handler and watch it line up with the
   strace output. One event, three views, in lesson one.
2. **printk and the ring buffer** — `dmesg -w`, log levels → a real printk in a
   driver → printk variables at different levels. (The thing you build *is* an
   observability mechanism.)
3. **/proc is code, not files** — `cat /proc/self/status` → a small seq_file
   handler → a module that creates a `/proc` entry. A window across the boundary,
   built by hand.
4. **The kernel narrates itself** — enable a tracepoint/function tracer via
   debugfs → attach a kprobe (via bpftrace) to the function you printk'd in lesson
   1, *with no rebuild*. The dynamic-tracing superpower, against code already
   understood.

---

## 7. The Wheel of Misfortune (capstone mode)

Borrowed from Google SRE: replay incidents as a facilitated, blameless game so a
team learns from production failures without waiting for them to recur.

**Key advantage over the SRE original:** SRE can't safely re-break production, so
their wheel is necessarily tabletop. A guest kernel is disposable and
re-breakable on demand, so each incident becomes **live fire** — the fault is
injected into a real guest kernel + stack, the learner drives real tools against
a genuinely broken system, and the dmesg / latency / oops are all real. Closer to
a flight simulator than a tabletop game.

### Design principles

- **Symptom-first**: the learner is paged with what prod would show, nothing more.
- **Deterministic & resettable** by default; intermittency promoted to a *teaching
  target* at intermediate+ ("it only happens under load — how do you catch it?").
- **Score on evidence**, not on guessing the answer.
- **Facilitator role** — graduated hints, or an LLM role-playing the on-call lead
  that reacts to hypotheses and grades reasoning.
- **Blameless post-mortem** ending each scenario: walk the actual kernel code path
  and note what observability would have caught it faster. This ties the wheel
  back to the read-the-code skill.

Structurally the wheel is the application/assessment layer on top of the
Observe/Read/Touch lessons: the lessons build tool fluency and vocabulary; the
wheel forces synthesis under incident pressure.

### Scenario catalog (initial)

Each is authorable as: a guest image + an injected fault (patch / module / sysctl
/ workload) + a ground-truth post-mortem.

**Basic** (single subsystem, workhorse tools: strace / dmesg / proc)

- **The process that won't die** — service unresponsive, `kill -9` does nothing,
  load climbing. `top` shows state `D`; `/proc/<pid>/stack` shows where it's
  wedged. Injected via a slow virtual disk or a module that sleeps in a syscall.
  Teaches task states and uninterruptible sleep.
- **Mystery OOM kill** — service killed at random; the OOM report is in `dmesg`
  (who got picked, RSS, oom_score), corroborated by `/proc/meminfo` and the
  cgroup limit. Injected via an undersized cgroup memory limit + workload.
- **Works on my laptop** — novel software logs a cryptic failure absent on the
  dev's machine. `strace` reveals a syscall returning an unexpected errno
  (EMFILE/EPERM/ENOSPC), traced to `/proc/<pid>/limits` or a sysctl. The
  archetype of "prod-like environment differs from the laptop."

**Intermediate** (dynamic tracing, deeper reading, optional intermittency)

- **Fast except sometimes** — p99 spikes while averages look fine. Static tools
  can't catch it; reach for perf or a bpftrace latency histogram and off-CPU
  analysis to find time lost to a contended lock or runqueue latency. Injected via
  a coarse lock in the stack's out-of-tree module or CPU oversubscription.
- **The driver that oopses** — a specific operation triggers a kernel oops.
  Decode the stack trace, map the faulting function to the module's source, find
  the bug (e.g., missing null check on a `copy_from_user`), optionally with a
  KASAN-enabled guest pinpointing the line; confirm with a kprobe. The purest
  analog of the motivating scenario: third-party software ships a driver that
  interacts badly with the kernel.
- **Packets that vanish** — requests intermittently time out, no crash, no error.
  `ss`/`tcpdump` at the edge, then bpftrace on the `kfree_skb` tracepoint or
  conntrack inspection to find *where* frames die. Injected via a full conntrack
  table or a stray firewall rule. Teaches that "no error" doesn't mean "no kernel
  involvement."

---

## 8. Open Design Decisions

- **Lesson opening: mystery-first vs. build-first.** Current lean: mystery-first
  (observe something puzzling, then read and touch to demystify), for motivation
  and to match the "get to the point" goal.

DECISION: mystery-first.

- **Modules vs. kernel-proper.** Modules give a tighter loop and are the gentle
  default; kernel-proper rebuilds reserved for things modules can't do (syscalls,
  core paths) and for the "I changed the actual kernel" milestone.

DECISION: modules to start.

- **Determinism vs. intermittency** in scenarios — deterministic by default,
  intermittency as a deliberate intermediate+ challenge.

DECISION: deterministic for basic / early work.

---

## 9. Phase 1 (the first step to build)

A minimal but complete vertical slice that proves the whole approach:

1. The workbench `Dockerfile` + `harness/` QEMU runner (lean initramfs, serial
   capture).
2. Lessons 1–2 (syscall-is-the-door, printk) with working `check.sh`.
3. One basic Wheel scenario end-to-end (likely **Works on my laptop** — pure
   userspace + boundary, no heavy guest rootfs needed).

If that slice feels good to work through, the rest is mostly authoring more
directories against the same harness.
