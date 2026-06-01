# B3 — Latency & context

> **Beyond "what ran" to "what *stalled*."** B1 followed the path; B2 cut the noise.
> B3 is about *time and context*: the kernel ships purpose-built tracers that answer
> "what's the longest the kernel went with interrupts off?", "which functions are
> hot?", and "how close did we come to blowing the stack?" — and a *latency format*
> that decodes the context (irqs off? in a hardirq? preemption disabled?) of every
> line. This is the first lesson that uses the tracers Module B compiled into the
> kernel.

> **Working in the workbench.** Nothing to write — B3 runs four tracers and shows you
> the output. Every command is an `echo` into tracefs; the lesson lists them so you
> can re-run in `make shell`.
>
> *(Built your kernel before Module B? These tracers won't be there. The check
> detects that and tells you to `make kernel`. B1/B2 run on the stock kernel; B3/B4
> need the rebuild.)*

## Observe — the four views

```sh
make check LESSON=B3-latency-and-context
```

## Read

### A — the irqsoff latency tracer, and the context flags

`echo irqsoff > current_tracer` arms a tracer that records the **single longest region
the kernel spent with interrupts disabled**, and the call path that caused it:

```
# tracer: irqsoff
# latency: 37347 us, #68/68, CPU#0 | (M:PREEMPT(voluntary) VP:0, KP:0, SP:0 HP:0 #P:2)
#  => started at: irqentry_enter
#  => ended at:   irqentry_exit
#
#                  _-----=> irqs-off/BH-disabled
#                 / _----=> need-resched
#                | / _---=> hardirq/softirq
#                || / _--=> preempt-depth
#                ||| / _-=> migrate-disable
#                |||| /  delay
#  cmd     pid   ||||| time  |   caller
```

That column legend is the **latency format** — and it's the "context" half of this
lesson. Every trace line carries these flags, telling you the state the CPU was in:

| flag | means |
|---|---|
| `d` | **irqs off** (interrupts disabled) |
| `h` / `s` | in a **hardirq** / **softirq** |
| `N` | **need-resched** set (a higher-prio task is waiting) |
| digit | **preempt-depth** (nested `preempt_disable()`) |

Reading those flags is how you tell "this slow path ran with interrupts off" (bad —
it delayed every IRQ) from "this just took a while but was preemptible" (usually fine).

> **Sibling tracers** (same shape, swap `current_tracer`): `preemptoff` (longest
> preemption-disabled region), `preemptirqsoff` (either), and `wakeup` / `wakeup_rt`
> (scheduling latency — wakeup-to-running for the top-priority task).

### B — the function profiler: what's hot

`echo 1 > function_profile_enabled` counts every function and times it; read the
ranking from `trace_stat/function<cpu>`:

```
  Function                Hit    Time            Avg             s^2
  --------                ---    ----            ---             ---
  schedule                923    20703657 us     22430.83 us     1451931 us
  do_idle                 866    5806523 us      6704.992 us     12937808 us
  schedule_timeout        645    5398054 us      8369.076 us     ...
```

`Hit` = call count, `Time` = total, `Avg` = per call. (An idle guest is dominated by
`schedule`/`do_idle` — that's the scheduler parking the CPU.) This is the cheap way to
ask "where is the kernel spending its time?" without sampling tooling.

### C — the stack tracer: how close to the edge

`echo 1 > /proc/sys/kernel/stack_tracer_enabled` watches every function and remembers
the **deepest kernel stack ever seen**, broken down frame by frame:

```
        Depth    Size   Location    (11 entries)
        -----    ----   --------
  0)     2712      48   rcu_segcblist_enqueue+0x9/0x50
  4)     2464    1128   mas_wr_bnode+0xb50/0x24c0      <- 1128 bytes in one frame
  6)     1216     768   __mmap_region+0x766/0xe10
  9)      224      48   do_syscall_64+0xb4/0x350
```

The kernel stack is small and fixed (a few pages); a runaway recursion or a fat stack
frame (`mas_wr_bnode` here ate 1128 bytes) can overflow it and corrupt memory. The
stack tracer finds the worst offender *before* it bites.

### D — snapshot, and dump-on-oops

`echo 1 > snapshot` atomically swaps the live ring buffer into a **snapshot** buffer —
freeze "the last N events" at an interesting instant while tracing keeps running. Its
crash-time cousin is `echo 1 > /proc/sys/kernel/ftrace_dump_on_oops`: on a panic the
kernel dumps the trace buffer straight to the console, so you get the last thing that
happened before death even with no disk.

## Touch — try the others

```sh
T=/sys/kernel/tracing
echo wakeup_rt > $T/current_tracer ; cat $T/tracing_max_latency   # scheduling latency
echo preemptoff > $T/current_tracer                               # preempt-off regions
cat $T/trace_stat/function*                                       # full profiler, all CPUs
```

## A note on the numbers

You're on an emulated (TCG) guest, so absolute times are **wildly inflated** — a
37&nbsp;ms "irqs-off" latency would be alarming on real hardware (microseconds is
normal). The *skill* B3 teaches is reading these tools — the worst region, its path,
the context flags, the hot functions, the deepest stack — not trusting the emulator's
clock.

## Verification

Green when the log shows the **irqsoff** latency trace, the **function profiler**
table, and the **stack tracer** breakdown — i.e. all three tracers produced output.

## Why this is lesson B3

Performance and stability bugs are latency bugs: a lock held too long with irqs off, a
function quietly eating CPU, a stack creeping toward overflow. These tracers are how
you *see* them, and the latency-format flags are how you read the context that makes a
delay benign or dangerous — the groundwork for the latency Wheel and for B4's events.

## Further reading

- [docs.kernel.org — ftrace](https://docs.kernel.org/trace/ftrace.html) — the latency tracers (`irqsoff`/`preemptoff`/`wakeup`), the latency-format flags, `function_profile_enabled`, the stack tracer, and `snapshot`.
- [docs.kernel.org — Tracing index](https://docs.kernel.org/trace/index.html) — the rest of the tracer and event interfaces, including the events B4 uses.
