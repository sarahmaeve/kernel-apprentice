# B4 — Events & histograms

> **From "every function" to "the events that matter."** B1–B3 traced *functions*.
> But the kernel also exposes **tracepoints** — stable, named, structured events
> (`sched_switch`, `sys_enter`, `kfree_skb`, …) with typed fields. And it can
> **aggregate them in-kernel** with **hist triggers** — a tiny query language that
> turns "a million events" into "a sorted table of counts." This is the payoff of the
> tracing track: ask a question, get an answer, without a single line of userspace.

> **Working in the workbench.** This is a CHALLENGE — you write one **hist trigger**
> in `trigger.hist`. Needs the Module B kernel (the check tells you if you must
> `make kernel`).

## Observe — it starts RED

```sh
make check LESSON=B4-events-and-histograms
```

The shipped `trigger.hist` keys the histogram by `___` — not a real field — so the
kernel rejects it and there's no histogram. **RED** until you key it correctly.

## The events interface (read this — it's the lesson)

Every tracepoint lives under `/sys/kernel/tracing/events/<subsystem>/<event>/` with:

| file | what it is |
|---|---|
| `format` | the event's **fields** and types — read this to know what you can key/filter on |
| `enable` | `echo 1` to start recording the event |
| `filter` | a predicate, e.g. `echo 'id == 257' > filter` (only `openat`) |
| `trigger` | attach actions — including **histograms** |

Subsystems worth knowing: `syscalls` / `raw_syscalls`, `sched` (`sched_switch`,
`sched_wakeup`), `irq`, `net` (`net_dev_xmit`, `kfree_skb`), `block`, `ext4`.
`set_event_pid` (top level) scopes *all* events to one task, the way `set_ftrace_pid`
did for the function tracer.

## The challenge — write the hist trigger

`raw_syscalls/sys_enter` fires on **every syscall** and carries an `id` field (the
syscall number). In `trigger.hist`, write a hist trigger that **buckets by syscall
id**, so the run produces a per-syscall histogram. The hints have the field name and
the exact line if you need them.

A hist trigger is a one-liner: `hist:keys=<field>[,<field>]:sort=<field>`. Once it's
right, the check applies it, runs a workload, and reads
`events/raw_syscalls/sys_enter/hist`:

```
# trigger info: hist:keys=id:vals=hitcount:sort=hitcount:size=2048 [active]

{ id:          0 } hitcount:         17     <- read(2)
{ id:        257 } hitcount:         18     <- openat(2)
{ id:         16 } hitcount:         16     <- ioctl(2)
...
Totals:
    Hits: 600
    Entries: 30
```

That's the whole skill: pick a tracepoint, pick a key, read the table. Key by two
fields for a breakdown; add `:sort=hitcount` to rank; add a `filter` to scope.

## Touch — push it further (in `make shell`)

```sh
T=/sys/kernel/tracing
echo 'hist:keys=next_comm:sort=hitcount' > $T/events/sched/sched_switch/trigger
cat $T/events/sched/sched_switch/hist          # which commands got scheduled, ranked
echo 'id == 257' > $T/events/raw_syscalls/sys_enter/filter   # then re-read the hist
```

## Verification

Green when the histogram is bucketed by syscall id — rows like `{ id: N } hitcount: M`.

Reset to the unsolved skeleton any time:

```sh
make reset LESSON=B4-events-and-histograms
```

## Why this is lesson B4

Hist triggers are how you answer "what is the kernel actually doing?" at scale —
which syscalls dominate, which process thrashes the scheduler, where packets drop —
with zero overhead from shipping events to userspace. It's the capstone of the tracing
track and the tool the latency Wheel rewards.

## Further reading

- [docs.kernel.org — Event Tracing](https://docs.kernel.org/trace/events.html) — the events interface: `format`, `enable`, `filter`, `trigger`, and `set_event_pid`.
- [docs.kernel.org — Histogram Triggers](https://docs.kernel.org/trace/histogram.html) — the full hist-trigger language: keys, values, sort, stacktrace keys, and synthetic events.
