# B2 — Trace just what matters

> **The firehose is the enemy.** A whole-kernel trace is millions of lines a second;
> the skill is narrowing to *your* signal. B2 has two halves: **instrument** the code
> you care about with `trace_printk()` (printk's low-overhead cousin, into the trace
> buffer), and **isolate** it with per-module and per-PID filters plus `trace_marker`
> brackets. B1 taught you to follow the path; B2 teaches you to cut the noise.

> **Working in the workbench.** This is a CHALLENGE — you add two `trace_printk()`
> calls to `module/b2_worker.c`. (Runs on the stock kernel; no rebuild needed.)

## Observe — it starts RED

```sh
make check LESSON=B2-trace-just-what-matters
```

`module/b2_worker.c` exposes `/proc/b2-go`; writing to it runs three phases —
`parse`, `compute`, `emit` — but they run in **silence**, so the check is **RED**:
the trace shows none of `b2: parse`, `b2: compute`, `b2: emit`.

## The challenge — make every phase narrate the trace

Make each phase write a line to the trace ring buffer (`/sys/kernel/tracing/trace`)
carrying its marker — **`b2: parse`**, **`b2: compute`**, **`b2: emit`**. Writing to
the trace buffer is the cheap, hot-path-safe alternative to flooding the kernel log,
and the line shows up inline with the function trace and your `trace_marker` notes.
The graduated hints below cover the *how* if you need it.

## The isolation toolkit (the recipe the check runs)

| Tool | What it does |
|---|---|
| `echo :mod:b2_worker > set_ftrace_filter` | function tracer sees **only this module's** functions |
| `echo $$ > set_ftrace_pid` | …and **only the triggering task** |
| `echo "…" > trace_marker` | drop a **userspace annotation** into the trace, inline |
| `echo 0/1 > tracing_on` | **enable/disable** the whole buffer around your window |

Together they turn "the whole kernel, forever" into "this module, this process, this
moment" — with your `trace_printk` notes threaded through.

## Touch — graduated hints

<details><summary>Hint 1 — what writes to the trace buffer?</summary>

`printk` would flood the kernel log; the trace buffer's own printf is
**`trace_printk()`** — same format args as `printk`, but it lands in
`/sys/kernel/tracing/trace`. One call per phase is all you need
(`#include <linux/kernel.h>` is already there).
</details>

<details><summary>Hint 2 — what must each line contain?</summary>

The check greps the trace for the literal substrings `b2: parse`, `b2: compute`, and
`b2: emit`. Each phase's format string must contain its marker.
</details>

<details><summary>Hint 3 — the solution</summary>

```c
static noinline void phase_parse(int n)
{
	trace_printk("b2: parse %d bytes\n", n);
}

static noinline void phase_compute(int n)
{
	int sum = n * 3;

	trace_printk("b2: compute sum=%d\n", sum);
}

static noinline void phase_emit(int n)
{
	trace_printk("b2: emit %d bytes\n", n);
}
```
</details>

## Verification

Green when the trace shows all three annotations — `b2: parse`, `b2: compute`,
`b2: emit` — i.e. every phase narrates itself in the buffer.

Reset to the unsolved skeleton any time:

```sh
make reset LESSON=B2-trace-just-what-matters
```

## Why this is lesson B2

Real traces drown you. `trace_printk` + the filters are how every kernel developer
turns a million-line haystack into the dozen lines that matter — the prerequisite for
the latency and histogram work in B3/B4.

## Further reading

- [docs.kernel.org — ftrace](https://docs.kernel.org/trace/ftrace.html) — `trace_printk`, `trace_marker`, `set_ftrace_pid`, and the `:mod:` filter syntax.
- [docs.kernel.org — Tracing index](https://docs.kernel.org/trace/index.html) — the rest of the tracer and event interfaces Module B builds on.
