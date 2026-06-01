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
`parse`, `compute`, `emit`. Only **parse** annotates the trace so far (the worked
example), so the check is **RED**: the trace is missing `b2: compute` and `b2: emit`.

## The challenge — make every phase narrate the trace

Add a `trace_printk()` to `phase_compute()` and `phase_emit()` so the trace shows a
line containing **`b2: compute`** and **`b2: emit`** respectively — mirroring the
`parse` example:

```c
trace_printk("b2: parse %d bytes\n", n);   /* already there, in phase_parse */
```

`trace_printk()` writes into the trace ring buffer (`/sys/kernel/tracing/trace`), not
the kernel log — cheap enough to leave in a hot path while you debug, and it shows up
inline with the function trace and your `trace_marker` notes.

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

<details><summary>Hint 1 — where do the annotations go?</summary>

In `module/b2_worker.c`, `phase_compute()` and `phase_emit()` have a
`TODO(B2)` where the `trace_printk()` should go. `phase_parse()` shows the shape.
</details>

<details><summary>Hint 2 — what must the line contain?</summary>

The check greps the trace for the literal substrings `b2: compute` and `b2: emit`.
Your format string must contain those — e.g. `trace_printk("b2: compute sum=%d\n", n*3);`.
</details>

<details><summary>Hint 3 — the solution</summary>

```c
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
