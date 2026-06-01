# B1 — Follow the path

> **One question, four moves.** "What calls what, and who called *this*?" — answered on
> a **live** kernel, no rebuild. A tool *shows* you the call graph, the trace *explains*
> the path, and you *reach in* and re-aim the filter yourself. This is the foundation of
> the whole tracing track: lesson 04 proved the kernel will narrate one function; B1
> teaches you to follow the narration through the call graph and back to the caller.

> **Working in the workbench.** Nothing to write — B1 drives ftrace through tracefs and
> shows you the four moves. (Everything here is `echo`-into-a-file; the lesson page lists
> the exact commands so you can re-run them in `make shell`.)

## Observe — the tool shows it

```sh
make check LESSON=B1-follow-the-path
```

> **Module B note:** B1 and B2 run on the stock kernel; **B3 (latency) and B4
> (histograms) need extra tracers compiled in**. If you built your kernel before
> Module B landed, run `make kernel` once to pick them up (it's incremental).

All four views run against the live kernel via `/sys/kernel/tracing`:

- **A · function_graph** — the *nested call graph* rooted at a function, with per-call
  timing (`func() { … }`), not just a flat list.
- **B · `set_ftrace_filter` + wildcard** — narrow the firehose: `*getpid*` resolves to
  every matching function before you trace.
- **C · `func_stack_trace`** — *who calls it*: the caller chain up to the syscall entry.
- **D · `trace` vs `trace_pipe`** — a re-readable snapshot vs a draining stream.

## Read — the trace explains it

**function_graph** (`current_tracer=function_graph`, scoped with `set_graph_function`):

```
 # CPU  DURATION              FUNCTION CALLS
 1)               |  __do_sys_getpid() {
 1)   0.180 us    |    __task_pid_nr_ns();
 1)   0.940 us    |  }
```

The `{ … }` nesting *is* the path; the `DURATION` column is where time went. (getpid is
shallow on purpose — try graphing `vfs_*` or `do_sys_openat2` to see real depth.)

**Wildcard filter** — `echo '*getpid*' > set_ftrace_filter`, then read it back:

```
__x64_sys_getpid
__do_sys_getpid
```

The kernel resolves the glob against `available_filter_functions` (thousands of names);
the filter is what the tracer will actually watch.

**Who calls it** — `echo 1 > options/func_stack_trace`:

```
   trigger-72  [001] .....  __do_sys_getpid <-__x64_sys_getpid
   trigger-72  [001] .....  <stack trace>
 => __do_sys_getpid
 => __x64_sys_getpid
 => do_syscall_64
 => entry_SYSCALL_64_after_hwframe
```

The `<-` column already names the *immediate* caller on every line; `func_stack_trace`
unwinds the **whole** chain — here, back through `do_syscall_64` to the syscall entry.

**`trace` vs `trace_pipe`** — `cat trace` is a re-readable snapshot of the ring buffer;
`cat trace_pipe` *consumes* as it streams (great for "watch it live," useless for "read
it twice"). Knowing which to use is half of not losing your data.

## Touch — re-aim it yourself

In `make shell`, boot a guest and try your own targets:

```sh
T=/sys/kernel/tracing
echo function_graph > $T/current_tracer
echo 'vfs_*'        > $T/set_graph_function   # graph the VFS layer instead
grep -c .           $T/available_filter_functions   # how many functions you *could* trace
echo '*alloc*'      > $T/set_ftrace_filter          # try a different wildcard
```

## Verification

Green when the captured log shows the **function_graph** call path and a
**`func_stack_trace`** caller stack — i.e. you can both follow the path down and trace it
back up.

## Why this is lesson B1

Every later tracing skill — events, histograms, latency — starts from "narrow to what
matters and see the path." Filtering, wildcards, the call graph, and `trace` vs
`trace_pipe` are the muscle memory the rest of Module B assumes.

## Further reading

- [docs.kernel.org — ftrace](https://docs.kernel.org/trace/ftrace.html) — the reference for `current_tracer`, `set_ftrace_filter`, `function_graph`, `func_stack_trace`, and `trace` vs `trace_pipe`.
- [docs.kernel.org — Tracing index](https://docs.kernel.org/trace/index.html) — the map of every tracer and event interface the rest of Module B builds on.
