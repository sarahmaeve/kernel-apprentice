# 04 — The kernel narrates itself

> **One event, three views — the payoff.** In lesson 01 you added a `printk` and
> **rebuilt** to make `getpid` speak. Here you make the *same* function speak on an
> **already-running** kernel, in milliseconds, **with no rebuild at all**. That's
> the dynamic-tracing superpower — and it's how you debug a box you can't recompile.

> **Working in the workbench.** No module, no kernel edit. This lesson drives the
> kernel's built-in tracing from userspace (`echo`/`cat` into `tracefs`).

## The mystery

The running kernel is already wired for instrumentation. Every function has an
`fentry` hook (that's **ftrace**), and you can drop a software breakpoint on almost
any instruction (that's a **kprobe**) — all at runtime, no source, no compile. The
kernel can narrate which functions run and what they're doing, on demand.

You'll point that narration at `__do_sys_getpid` — the exact handler you edited in
lesson 01 — and watch it report itself, having changed *nothing* in the build.

## Observe — the function tracer narrates

`tracefs` lives at `/sys/kernel/tracing`. Turn on the function tracer, narrow it to
one function, and watch:

```sh
cd /sys/kernel/tracing
echo __do_sys_getpid > set_ftrace_filter   # only narrate this function
echo function       > current_tracer
echo 1 > tracing_on ;  ./trigger  ; echo 0 > tracing_on
cat trace                                    # -> __do_sys_getpid <-do_syscall_64
```

The kernel just told you that function ran, and who called it — no rebuild.

## Read — how it can do that

- **ftrace** relies on a tiny `call __fentry__` planted at the start of every
  function by the compiler (`-pg`). At runtime the kernel patches those sites to
  jump into the tracer. (That's the `ftrace: allocating … entries` line you see at
  boot.)
- **kprobes** go further: they replace an instruction *anywhere* with a breakpoint,
  run your handler, then single-step the original. `kprobe_events` exposes this
  through `tracefs` so you can register one with a single `echo`.

Neither needs the source or a compiler. The instrumentation is *already in the
kernel you booted*.

> **Which symbol?** `SYSCALL_DEFINE0(getpid)` from lesson 01 compiles to
> **`__do_sys_getpid`** — the body you edited. The x86 entry `__x64_sys_getpid`
> (what you'll see first in `/proc/kallsyms`) just calls it. We trace the body.

## Touch — attach a kprobe, live

```sh
make check LESSON=04-kernel-narrates-itself
```

The guest registers a kprobe on the lesson-01 handler and fires it:

```sh
cd /sys/kernel/tracing
echo 'p:ka_getpid __do_sys_getpid' > kprobe_events   # define the probe — no rebuild
echo 1 > events/kprobes/ka_getpid/enable
echo 1 > tracing_on ;  ./trigger  ; echo 0 > tracing_on
cat trace                                              # -> ka_getpid: (__do_sys_getpid+0x0/…)
```

**PASS** when the trace shows `ka_getpid:` firing. Compare the effort to lesson 01:
there you edited C and waited for a kernel build; here you instrumented the running
kernel in one line. *That's* the move that works when you can't reproduce in a clean
lab or can't recompile the box.

## Verification

Green when the serial log contains `ka_getpid:` — a kprobe you attached to the live
kernel fired on the getpid handler. (The function-tracer view is shown too, as a
bonus second view.)

## Exploration (drive it yourself)

1. **Capture an argument.** `kprobe_events` can record values, e.g. a probe on
   `do_sys_openat2` that grabs the filename. Read the syntax in *Further reading*.
2. **The friendly frontend.** `bpftrace` (installed in the workbench) is a one-liner
   wrapper over exactly this machinery — but the raw `tracefs` interface you used
   here is what it drives underneath.
3. **Why this beats a rebuild.** When would dropping a `printk` (lesson 01) be the
   wrong tool, and a kprobe the right one? (Hint: production, no source, can't
   reboot.)

## Why this is lesson four

This closes the apprentice arc. You can now make any function in a *running* kernel
report itself — the skill that turns "I can't reproduce it on my laptop" into "let
me watch the real box tell me what it's doing."

## Further reading

Canonical references for deeper exploration:

- [docs.kernel.org — ftrace, the Function Tracer](https://docs.kernel.org/trace/ftrace.html) — the `tracefs` interface and every tracer it offers.
- [docs.kernel.org — Kprobe-based Event Tracing](https://docs.kernel.org/trace/kprobetrace.html) — the `kprobe_events` syntax you used, including capturing arguments.
- [docs.kernel.org — Kernel Probes (Kprobes)](https://docs.kernel.org/trace/kprobes.html) — how kprobes work underneath.
