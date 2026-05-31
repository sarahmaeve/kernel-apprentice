# C1 — Read an OOM report

> **One event, three views.** When the kernel can't find memory, it kills a process
> and leaves a detailed report. That report is one of the most information-dense
> things the kernel ever prints — and reading it fluently is the whole skill. Here a
> tool *shows* you a real OOM, the report *explains* who and why, and you *reach in*
> at `/proc` and the cgroup to corroborate.

> **Working in the workbench.** Nothing to write — this lesson triggers an OOM and
> hands you the report. (The Wheel scenario *Mystery OOM kill* is the same machinery,
> symptom-first, when you want to be tested on it.)

## Observe — the tool shows it

```sh
make check LESSON=C1-read-an-oom-report
```

A "service" runs in a cgroup capped at `memory.max = 16M`, grows past it, and the
**cgroup OOM killer** reaps it. The check dumps the report, `/proc/meminfo`, and the
cgroup's `memory.events`.

## Read — the report explains it

```
hog invoked oom-killer: gfp_mask=0x..., order=0, oom_score_adj=0
memory: usage 16384kB, limit 16384kB, failcnt 73
Tasks state (memory values in pages):
[  pid  ]   uid  tgid total_vm      rss ... oom_score_adj  name
[    67 ]     0    67     4358     4064 ...             0   hog
oom-kill:constraint=CONSTRAINT_MEMCG,...,oom_memcg=/svc,task=hog,pid=67
Memory cgroup out of memory: Killed process 67 (hog) total-vm:17432kB, anon-rss:16256kB, ...
```

Field by field:

- **`hog invoked oom-killer`** — who was *asking* for memory when reclaim failed (not
  necessarily the victim).
- **`memory: usage 16384kB, limit 16384kB`** — the cgroup is at its cap; reclaim
  couldn't free enough.
- **`Tasks state` table** — every candidate, with `rss` and **`oom_score_adj`**. The
  killer scores tasks (roughly by memory footprint, adjusted by `oom_score_adj`) and
  picks the highest.
- **`constraint=CONSTRAINT_MEMCG`** — the *tell*: a **cgroup** limit was hit, not the
  whole machine (`CONSTRAINT_NONE`). This is "raise the container's limit," not "buy
  RAM."
- **`Killed process 67 (hog) ... anon-rss:16256kB`** — the **victim**: pid, name, and
  how much resident memory it held when reaped (~the 16M cap).

## Touch — corroborate at /proc and the cgroup

The check also shows the evidence you'd gather yourself:

```sh
grep -E 'MemTotal|MemFree|MemAvailable|AnonPages' /proc/meminfo  # system memory
cat /cg/svc/memory.events                                        # oom_kill count
# (a live process: cat /proc/<pid>/oom_score , /proc/<pid>/status VmRSS)
```

`memory.events`' `oom_kill` counter ticking is the machine-readable version of the
report — what you'd alert on.

## Verification

Green when the captured log contains the OOM report (with the per-task table) and
`/proc/meminfo` — you have a real report in front of you to read.

## Why this is lesson C1

"Service died, no error in its logs" is one of the most common production pages, and
nine times out of ten the answer is in the OOM report — *if* you can read it. Now you
can: victim, footprint, and the crucial global-vs-cgroup constraint.

## Further reading

Canonical references for deeper exploration:

- [docs.kernel.org — Control Group v2](https://docs.kernel.org/admin-guide/cgroup-v2.html) — `memory.max`, `memory.events`, and how the cgroup OOM killer chooses a victim.
- [docs.kernel.org — Concepts overview (memory management)](https://docs.kernel.org/admin-guide/mm/concepts.html) — reclaim and the OOM killer, the machinery behind the report.
