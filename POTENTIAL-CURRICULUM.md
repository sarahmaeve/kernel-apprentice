# POTENTIAL-CURRICULUM.md — the full apprenticeship

*A living planning doc, like [DESIGN.md](DESIGN.md) — meant to be argued with, not
treated as fixed. It sketches how the apprentice arc — now **14 lessons and three Wheel
scenarios built** across modules A, B, C, E, G and H (01–07, H1, B1–B4, C1–C2, plus the
Works-on-my-laptop, Mystery-OOM-kill and Fast-except-sometimes Wheels) — grows into a
full curriculum that
**supplants the existing kernel-debugging courses and books** — with a live, breakable
kernel and automated PASS/FAIL instead of lectures.*

---

## 1. Lesson grain — how big is a lesson?

A **lesson** anchors on ONE substantial observable moment, walked through
Observe → Read → Touch, ending in an automated check. Not one command — one *aha*.

This is deliberately **coarser than the micro-topics of video courses.** A
3-minute clip on "wildcard characters in filters" is the right grain for video;
for us it's one *bullet inside* a lesson that also boots a kernel and grades you.
So we **combine related micro-topics into fewer, meatier lessons.**

- **Lesson** = one Observe→Read→Touch arc + one `check.sh` (about the size of 01–04).
- **Module** = 2–4 lessons + one Wheel scenario that forces synthesis under pressure.
- If a topic can't carry its own *symptom → evidence* payoff, it's a **section of a
  lesson**, not a lesson of its own.

A 16-video ftrace course therefore becomes ~3 lessons here (see §5). Erring coarse
keeps momentum (fewer boots, fewer dirs) and keeps every lesson worth its check.

## 2. The spine we cover

The debugging courses and books converge on nearly one syllabus. We cover this
spine — deep and hands-on:

1. **The boundary** — syscalls, fds, signals, mmap, ioctl, `/proc` · `/sys` · `debugfs`
2. **Instrumentation** — printk, dynamic debug, `trace_printk`
3. **Tracing / observability** — ftrace, kprobes, perf, eBPF/bpftrace *(the core)*
4. **Memory** — KASAN, UBSAN, kmemleak, SLUB debug
5. **Concurrency** — lockdep, KCSAN
6. **Crash / panic** — oops decoding, kdump + `crash`, KGDB

**Out of scope** (DESIGN §1): kernel-internals for their own sake, becoming an
upstream contributor, exotic/rare bugs. We teach reading + tracing + debugging
software↔kernel interactions, symptom-first.

**Adjacent but out of scope:** static analysis (Sparse, Smatch, Coccinelle) and
fuzzing (syzkaller / syzbot) — "finding latent bugs during *development*," a
contributor concern. We nod to them in Further-reading, not teach them.

## 3. Models we supplant

| Model | Format | We supplant it by… |
|---|---|---|
| [Bootlin — *Debugging/profiling/tracing*](https://bootlin.com/training/debugging/) | instructor-led labs | self-serve; a persistent breakable kernel; automated grading |
| [LF **LFD445** — *Kernel Debugging*](https://training.linuxfoundation.org/training/linux-kernel-debugging-lfd445/) | paid, instructor-led | symptom-first incidents; no scheduling |
| [Billimoria — *Linux Kernel Debugging* (Packt)](https://github.com/PacktPublishing/Linux-Kernel-Debugging) | book (passive) | you drive a live kernel, not read about one |
| Udemy *ftrace* course | video (passive) | each topic becomes a graded, driveable lesson (§5) |
| Gregg — *BPF Performance Tools* | book / talks | the latency Wheel makes you *find* it under pressure |
| Babka (SUSE) — *Linux Kernel Debugging* lecture | slides (free) | we make you *drive* the oops/crash, not read 25 slides about one |

Common edge over all of them: a real, breakable kernel you drive, with automated
PASS/FAIL and live-fire incidents. A video can't fail your build; a book can't page
you with a `D`-state process.

## 4. Module map

**Legend:** ✅ built · 🔲 proposed.  States: **READY** (run + observe, no code to
write) · **CHALLENGE** (write or fix code to pass) · **LIVE FIRE** (diagnose a
deliberately broken box).

### A · The Boundary
*Goal: fluency at the syscall boundary and the `/proc` / `/sys` / `debugfs` surfaces.*

| Lesson | State | Absorbs / notes |
|---|---|---|
| 01 The syscall is the door | CHALLENGE ✅ | syscall → handler → printk |
| 03 /proc is code, not files | READY ✅ | seq_file, proc_ops; `/sys`, debugfs by analogy |
| A1 The other doors | CHALLENGE 🔲 | fds, signals, mmap, ioctl in one arc |
| **Wheel — Works on my laptop** | LIVE FIRE ✅ | rlimits / EMFILE |

### B · Tracing & Observability  — *flagship; supplants the full Udemy ftrace course + LFD445*
*Goal: see a live kernel without rebuilding it. The ~60-clip ftrace course collapses
into **4 new lessons** here (see §5) — we teach each mechanism on one real example
and push the exhaustive breadth to Further-reading.*

| Lesson | State | Absorbs / notes |
|---|---|---|
| 02 printk and the ring buffer | READY ✅ | log levels, the ring buffer |
| 04 The kernel narrates itself | READY ✅ | ftrace function tracer + kprobe intro |
| B1 Follow the path | READY ✅ | function + function_graph, set_ftrace_filter, wildcards, "who calls X", trace vs trace_pipe |
| B2 Trace just what matters | CHALLENGE ✅ | set_ftrace_pid, per-module filter, trace_printk, trace_marker, enable/disable |
| B3 Latency & context | READY ✅ | irqsoff/preempt/wakeup latency tracers, context flags, function profiler, stack tracer, snapshot, ftrace-dump-on-oops |
| B4 Events & histograms | CHALLENGE ✅ | tracepoint events interface, format/filter/triggers, **hist triggers**, sched/irq/net/fs events, set_event_pid |
| **Wheel — Fast except sometimes** | LIVE FIRE ✅ | p99 / tail latency, localized with function_graph |

*Frontends (`trace-cmd`, `bpftrace`, `perf`) are introduced as the ergonomic layer
over the raw tracefs **within** B1–B4, not a separate lesson. A dedicated **perf /
eBPF** sub-track (sampling profiles, flame graphs, libbpf) is a later extension —
the Udemy course is ftrace-specific, so it isn't needed to supplant it.*

*Config: B's later lessons need a few cheap tracers in the base kernel —
`FUNCTION_GRAPH_TRACER`, `IRQSOFF_TRACER`, `PREEMPT_TRACER`, `SCHED_TRACER`,
`STACK_TRACER`, `FUNCTION_PROFILER`, `HIST_TRIGGERS` — **now added** (see
`harness/config/tutorial.config`). B1/B2 run on the stock kernel; B3/B4 want the
rebuild, and their checks self-detect a stale kernel and say `make kernel`.*

### C · Memory
*Goal: diagnose memory misbehavior from the report, not a guess.*

| Lesson | State | Absorbs / notes |
|---|---|---|
| C1 Read an OOM report | READY ✅ | oom_score, `/proc/meminfo`, cgroup limit (reuses base `CONFIG_MEMCG`) |
| C2 KASAN catches you | CHALLENGE ✅ *(optional)* | three bugs — out-of-bounds + use-after-free + double-free; read each report, fix it. Runs on a **dedicated KASAN kernel** (`make kasan-kernel`), opt-in and off the graded count |
| **Wheel — Mystery OOM kill** | LIVE FIRE ✅ | undersized cgroup + workload; grades on `constraint=CONSTRAINT_MEMCG` |

### D · Concurrency, Locking & Hangs
| Lesson | State | Absorbs / notes |
|---|---|---|
| D1 lockdep on a deadlock | CHALLENGE 🔲 | ABBA ordering bug; lockdep names it; fix the order |
| D2 KCSAN finds a race | CHALLENGE 🔲 | data race; add the missing sync |
| D3 Lockups & hung tasks | READY 🔲 | soft/hard lockup (watchdog + NMI), `khungtaskd`; the mechanism behind the D-state Wheel |
| **Wheel — The process that won't die** | LIVE FIRE 🔲 | uninterruptible `D` sleep; `khungtaskd` fires; `/proc/<pid>/stack` |

### E · Crashes, Oops & Panic
| Lesson | State | Absorbs / notes |
|---|---|---|
| E0 Anatomy of an oops | READY 🔲 | dissect a real oops field-by-field: BUG vs WARN vs panic, `UD2`, taint flags, RIP, call trace, registers; decode RIP → file:line (`faddr2line`, `decode_stacktrace.sh`) |
| 05 The driver that oopses | CHALLENGE ✅ | apply E0 — trigger, read, find, fix a NULL-deref bug |
| E1 Post-mortem with `crash` | READY 🔲 | kexec/kdump → `/proc/vmcore` → `crash` `bt`/`ps`/`struct`; ORC unwinder |
| **Wheel — The driver that oopses** | LIVE FIRE 🔲 | intermediate; the KASAN overlay kernel (built for C2) is available |

*(The Babka deck spends ~25 slides on E0 alone — reading an oops cleanly is a whole
lesson, and the prerequisite for everything else in this module.)*

### F · Networking  *(advanced / optional)*
| Lesson | State | Absorbs / notes |
|---|---|---|
| F1 Where packets die | CHALLENGE 🔲 | ss, tcpdump, `kfree_skb` tracepoint, conntrack |
| **Wheel — Packets that vanish** | LIVE FIRE 🔲 | full conntrack table / stray rule |

### G · Modification  — *hands-on capstone*
*Goal: change the kernel to a spec, the milestone these courses only describe.*

| Lesson | State | Absorbs / notes |
|---|---|---|
| 06 Instrument it yourself | CHALLENGE ✅ | implement a kprobe counter exposed via `/proc` |
| 07 A character device with ioctl | CHALLENGE ✅ | open/read/write/ioctl so a userspace test passes |
| G1 Patch to test a fix | CHALLENGE 🔲 | fix a confirmed Wheel bug — "I changed the actual kernel" |

### H · Interactive & live debugging  — *leverages our QEMU harness (a differentiator)*
*Goal: drive a live kernel interactively — what a video or book can only describe.*

| Lesson | State | Absorbs / notes |
|---|---|---|
| H1 Step through the live kernel with gdb | READY ✅ | QEMU's gdbstub (`-s`): break on `__do_sys_getpid`, inspect locals — source-level kernel debugging, free |
| H2 The panic button — SysRq | READY 🔲 | `/proc/sysrq-trigger`: dump tasks (`t`), CPU stacks (`l`), blocked (`w`), memory (`m`) — pull state from a wedged box |
| H3 kgdb / kdb over serial | READY 🔲 | `kgdboc=ttyS0`, `sysrq-g`, kdb in-kernel (advanced; QEMU's gdbstub usually beats it) |

*Why a module of its own: the Babka deck shows kgdb setup is fiddly; QEMU's built-in
gdbstub gives us source-level live-kernel debugging almost for free — a thing the
lecture/video models can't easily demo. Pairs naturally with E (oops) and D (hangs).*

## 5. The tracing track, micro → combined (worked example)

The full Udemy ftrace course is **~60 clips across 5 sections**. It collapses into
**4 new lessons** (B1–B4) plus the two we already have — each a full
Observe→Read→Touch with a check:

| Udemy section (clips) | → our lesson |
|---|---|
| ftrace basics — tracefs files, tracers, function_graph, filtering, wildcards, trace vs trace_pipe, who-calls | **B1 Follow the path** |
| isolating signal — tracing a process, tracing a module, trace_printk, trace_marker, enable/disable | **B2 Trace just what matters** |
| latency & internals — irqs-off/need-resched/preempt context, latency tracers, function profiling, stack tracer, snapshot, ftrace-dump-on-oops | **B3 Latency & context** |
| tracepoints & events — events interface, format/filter/triggers, histograms, sched/irq/net/fs/ext4 events, set_event_pid | **B4 Events & histograms** |
| trace-cmd frontend — list/start/stop/record/report/extract/filtering | folded into B1–B2 as "the ergonomic frontend" |
| how userspace gets into the kernel | callback to **01 The syscall is the door** |

**Deliberately compressed:** the course enumerates *every* event subsystem (USB,
ext4, net, …) and *every* `trace-cmd` subcommand. We teach the **mechanism** on one
real example per lesson and point Further-reading at the rest — the skill transfers,
the catalog doesn't need re-teaching.

## 6. Suggested build order

*Status so far: A, **all of B** (02/04 + B1–B4 + its Wheel), C (all of it), E (05),
G (06/07) and H1 are built — 14 lessons and 3 Wheels across six modules. The opt-in
KASAN overlay kernel, the Module B tracer config, and `make reset` are built too.
Remaining priorities below.*

1. **G — 06, 07** ✅ done.
2. **B — B1–B4 + its Wheel** ✅ done (the flagship tracing track — the most direct
   supplant of the Udemy/LFD445 ftrace material; the base-config tracer bump shipped
   with it).
3. **E — 05** ✅ done (the oops-fix); the driver Wheel (E) is still 🔲.
4. **C / D**: **C done** (C1 / C2 / Wheel — KASAN ships as `make kasan-kernel`, a
   separate opt-in kernel rather than a base-config change). **D** (locking) is next,
   gated behind a lockdep / KCSAN overlay.
5. **F**: networking last — it needs the most extra guest plumbing.

## 7. Conventions (how a new lesson is added)

- A directory with `README.md` (lesson + challenge + graduated hints + further
  reading), `check.sh`, source/starter files, and a CRT-phosphor `index.html`.
- Wire it into `harness/check.sh` (dispatcher), `harness/gen-status.sh` (the N/total
  count), the root `index.html` curriculum table + legend, and the inter-lesson nav.
- **CHALLENGE** lessons ship buggy/skeleton code on `main` (so the check is red), with
  the fix as the last graduated hint. `make reset [LESSON=…]` restores any solved
  lesson to its committed skeleton — git-restore for repo edits, re-extract for
  kernel-tree edits — and clears its pass-record, so prototyping and re-attempting are
  cheap (no `solutions` branch needed, as first sketched).
- Heavy debug configs stay out of the base kernel (they slow every boot). The
  established pattern (see C2) is a **separate opt-in kernel build** —
  `harness/build-kasan-kernel.sh` / `make kasan-kernel`, booted via the `KERNEL_IMAGE`
  override — rather than a base-config change; the same approach fits UBSAN, KCSAN,
  lockdep, `DEBUG_KMEMLEAK`, `SLUB_DEBUG`, `DEBUG_PAGEALLOC`. Module E also needs
  `crash` + kdump (`kexec-tools`, `makedumpfile`) added to the workbench image.
- Every external reference is verified to resolve before it's committed.
