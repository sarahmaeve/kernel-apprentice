# 06 — Instrument it yourself

> **CHALLENGE.** The lessons so far handed you working code to read. Now *you* write
> it. You're given a module skeleton and a spec; fill in two functions so the kernel
> counts an event and reports it through `/proc`. This is the synthesis of lesson 03
> (`/proc`) and lesson 04 (kprobes) — and your first taste of *modification*.

> **Working in the workbench.** Edit `module/counter.c` in this repo (host-editable,
> like any lesson file), then run `make check` from the host.

## The spec

Build `/proc/kernel-apprentice-count` so that **every read** prints exactly:

```
getpid calls: <N>
```

where `<N>` is the number of times `getpid` has been called since the module was
loaded.

## What you're given

`module/counter.c` already does the hard plumbing:

- registers a **kprobe** on `__x64_sys_getpid` (its handler fires on every getpid),
- creates the `/proc` entry, backed by a `seq_file` (like lesson 03),
- keeps an `atomic_t ka_count` for you to use.

Two functions are left as stubs marked `TODO`:

1. **`ka_pre_handler()`** — runs on each getpid call. Make it count.
2. **`ka_show()`** — runs on each `/proc` read. Make it print the spec line.

As shipped it compiles and loads, but the counter never moves and `/proc` is empty —
so the check is **red** until you implement both.

## Touch

Fill in the two TODOs, then:

```sh
make check LESSON=06-instrument-it-yourself
```

**PASS** when `/proc/kernel-apprentice-count` reports a **non-zero** count after the
test calls getpid 50 times. You'll have built a kernel instrument — by hand.

## Graduated hints

<details><summary>Hint 1 — counting (TODO 1)</summary>

The handler fires once per getpid. Bump the atomic counter:
`atomic_inc(&ka_count);`
</details>

<details><summary>Hint 2 — printing (TODO 2)</summary>

`seq_show` writes the file contents with `seq_printf`. Read the counter and print
the spec line:
`seq_printf(m, "getpid calls: %d\n", atomic_read(&ka_count));`
</details>

<details><summary>Hint 3 — both, together</summary>

```c
static int ka_pre_handler(struct kprobe *p, struct pt_regs *regs)
{
        atomic_inc(&ka_count);
        return 0;
}

static int ka_show(struct seq_file *m, void *v)
{
        seq_printf(m, "getpid calls: %d\n", atomic_read(&ka_count));
        return 0;
}
```
</details>

## Why this is lesson six

Lesson 03 gave you `/proc`; lesson 04 gave you kprobes. Here you combine them into a
tool *you* wrote — a counter that wasn't in the kernel before. That's the first step
of the modification milestone (DESIGN §6): not just reading the kernel, but adding
to it to answer a question it couldn't.

## Further reading

Canonical references for deeper exploration:

- [docs.kernel.org — Kernel Probes (Kprobes)](https://docs.kernel.org/trace/kprobes.html) — `register_kprobe`, pre-handlers, and what you can do in one.
- [docs.kernel.org — The seq_file Interface](https://docs.kernel.org/filesystems/seq_file.html) — the `/proc` output mechanism behind `ka_show`.
