# H2 — SysRq: the panic button

> **One event, three views.** When a box is so wedged that ssh is dead and nothing
> in userspace answers, one listener remains: the kernel itself. **SysRq** is its
> emergency intercom — single letters that dump state to the console no matter how
> bad things are. A module wedges a thread in **D state** on purpose; the SysRq
> dumps *show* it, the dump's fields *explain* who is stuck and where, and
> `/proc/<pid>/stack` lets you *reach in* and read the exact frames it sleeps
> under. Then you press the real panic button.

> **Working in the workbench.** Nothing to fix — the wedge is deliberate. This is
> the machinery behind "`kill -9` does nothing"; the planned Module D Wheel pages
> you with it under incident pressure.

## Observe — ask a wedged box for its state

```sh
make check LESSON=H2-sysrq-the-panic-button
```

The check loads `h2_wedge.ko`, which parks a kthread named `h2-wedged` in
`TASK_UNINTERRUPTIBLE`, then walks the letters via `/proc/sysrq-trigger`:

- **`t`** — every task: state + kernel stack. The whole zoo: `S` (sleeping,
  interruptible), `I` (idle kthreads), `R` (running) — and one `D`.
- **`w`** — only the **blocked** (D state) tasks. On a wedged box this is the
  letter you press first.
- **`m`** — memory state: free/used, per-zone, slab — an OOM-shaped overview
  without needing `/proc`.
- **`l`** — backtrace of all **active CPUs**: what is *on* the cores right now
  (where `t` shows every task, running or not).

On real hardware these are keyboard chords (`Alt+SysRq+<letter>`) or break
sequences on a serial console — which is why they work when nothing else does.
The `kernel.sysrq` sysctl mask gates only the keyboard path; a root write to
`/proc/sysrq-trigger` always works.

## Read — the D state, and where it sleeps

The `w` dump, verbatim from the captured log:

```
sysrq: Show Blocked State
task:h2-wedged       state:D stack:15000 pid:66    tgid:66    ppid:2      ...
Call Trace:
 <TASK>
 __schedule+0x4e3/0xf80
 ? __pfx_h2_wedge_fn+0x10/0x10 [h2_wedge]
 ? h2_wedge_fn+0x42/0x50 [h2_wedge]
 schedule+0x41/0x1a0
 h2_wedge_fn+0x42/0x50 [h2_wedge]
 kthread+0x10a/0x200
 ? __pfx_kthread+0x10/0x10
 ret_from_fork+0x17e/0x1a0
```

- **`state:D`** — `TASK_UNINTERRUPTIBLE`: not runnable, and signals — `kill -9`
  included — stay pending until it next runs, *which is exactly what it won't do*.
  D is normally a fleeting state around I/O; a task that **stays** D is the
  classic wedged-box symptom.
- **`ppid:2`** — its parent is `kthreadd`, the mother of all kernel threads: this
  one isn't a userspace process at all.
- **The trace, top down** — `__schedule` / `schedule` is *how* it sleeps (every
  sleeping task ends there); the first real frame below them — **`h2_wedge_fn`** —
  is *who chose to*. `?` frames are stack leftovers, not confirmed callers (E0),
  and `__pfx_*` symbols are function padding — skip both.

## Touch — the stack file, then the button itself

`/proc/<pid>/stack` is the per-task version of the same answer (root-only), and
it filters the scheduler frames for you:

```
[<0>] h2_wedge_fn+0x42/0x50 [h2_wedge]
[<0>] kthread+0x10a/0x200
[<0>] ret_from_fork+0x17e/0x1a0
[<0>] ret_from_fork_asm+0x1a/0x30
```

Top of what's left = the function that went to sleep: your module, named. This
file is the single fastest answer to "*where* is this process stuck?"

Then the finale — the letter the lesson is named for:

```
sysrq: Trigger a crash
Kernel panic - not syncing: sysrq triggered crash
CPU: 1 UID: 0 PID: 1 Comm: init Tainted: G           O        6.18.33 #8 ...
```

**`c`** panics the kernel *on command*, in whatever context pressed the button
(`Comm: init` — our init script did). Nothing survives; QEMU exits (`panic=-1`
plus `-no-reboot`). Deliberately crashing a wedged box sounds drastic, but with
kdump configured it is how you turn "hung, no idea why" into a corpse you can
autopsy — that's lesson E1 (planned). And the report it leaves carries everything
E0 taught: taint letters, call trace down to `sysrq_handle_crash`.

## Verification

Green when the captured log shows all four dumps (`Show State`, `Show Blocked
State`, `Show Memory`, `Show backtrace of all active CPUs`), `h2-wedged` in
`state:D` with `h2_wedge_fn` named in a stack, and the panic
(`Kernel panic - not syncing`).

## Why this is lesson H2

H1 debugged a live kernel from *outside*, through QEMU's gdbstub. SysRq is what
you have on a **real** wedged box, where there is no gdbstub: a serial console and
these letters are the last line, and the time to learn them is before the
incident. Pairs with Module D (the D state under real contention) and E1 (kdump
after the button).

## Further reading

Canonical references for deeper exploration:

- [docs.kernel.org — Linux Magic System Request Key Hacks](https://docs.kernel.org/admin-guide/sysrq.html) — every letter, the keyboard chords per architecture, and the `kernel.sysrq` enable mask.
- [docs.kernel.org — Documentation for /proc/sys/kernel/](https://docs.kernel.org/admin-guide/sysctl/kernel.html) — `sysrq`, `panic`, `panic_on_oops`, `hung_task_*`: the knobs around everything this lesson touched.
