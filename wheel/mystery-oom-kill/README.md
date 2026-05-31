# Wheel of Misfortune — "Mystery OOM kill"

> **Live fire, symptom-first.** The box is genuinely broken — a service keeps
> getting killed. Drive real tools; **score on the evidence you point at**, not on a
> guess (DESIGN §7).

---

## 📟 The page

> A service, `svc`, keeps **dying under load** — no crash, no error in its own logs,
> it's just *gone*, and the supervisor restarts it in a loop. It runs fine on a
> smaller workload, and fine on the dev laptop. Same binary, same inputs. Something
> outside the app is killing it. Find out **who, and why**.

Don't read the post-mortem until you've driven it.

## Run the scenario

```sh
make check LESSON=wheel/mystery-oom-kill
```

## Your job

1. **Reproduce & read the symptom.** The service vanishes; its own output stops
   mid-stride. Nothing in the app explains it.
2. **Ask the kernel.** When the kernel kills a process to reclaim memory, it leaves a
   detailed report in `dmesg`. Find it (`dmesg | grep -i oom`).
3. **Read the OOM report.** *Who* got picked (process, pid), how much it was using
   (`anon-rss`), its `oom_score_adj`, and — crucially — the **constraint**.
4. **Point at the evidence.** State it as: *"`svc` was OOM-killed by its **cgroup**
   memory limit (`constraint=CONSTRAINT_MEMCG`); `memory.max` = 16M, and its RSS hit
   the limit."* Corroborate with `/proc/meminfo` and `memory.events`.

## Read the OOM report

```
hog invoked oom-killer: gfp_mask=0x..., order=0, oom_score_adj=0
memory: usage 16384kB, limit 16384kB, failcnt N
...
oom-kill:constraint=CONSTRAINT_MEMCG,...,task=hog,pid=N
Memory cgroup out of memory: Killed process N (hog) total-vm:..., anon-rss:..., oom_score_adj:0
```

`constraint=CONSTRAINT_MEMCG` is the tell: the **whole machine didn't run out of
memory — *this process's cgroup* hit its limit.** That's the difference between "buy
more RAM" and "raise the container's limit (or fix the workload)."

## Graduated hints

<details><summary>Hint 1 — where's the evidence?</summary>

The app didn't log a thing because it didn't fail — it was *killed*. Ask the kernel:
`dmesg | grep -i oom` (or look for `Killed process`).
</details>

<details><summary>Hint 2 — global or cgroup?</summary>

Look at the `constraint=` field. `CONSTRAINT_NONE` means the whole box ran out;
`CONSTRAINT_MEMCG` means a **cgroup** limit was hit — only *this* service's memory
was capped.
</details>

<details><summary>Hint 3 — the limit</summary>

```sh
cat /cg/svc/memory.max      # the cap: 16M
cat /cg/svc/memory.events   # oom_kill count
```
The working set grew past 16M; the limit is too small for the workload.
</details>

## 🧾 Post-mortem (read after you've driven it)

<details><summary>open after you've driven it — ground truth + the lesson</summary>

**Ground truth.** The service runs in a cgroup with `memory.max = 16M`. Its working
set grows past 16M; the cgroup OOM killer reaps the biggest task in the cgroup (the
service). Nothing is wrong with the binary — the **limit is too small for the
workload** (equivalently, the workload is too big for the limit).

**Why it's the archetype.** Containers ship with memory limits; the same image that's
fine on a laptop (no limit) gets OOM-killed in prod (a tight `memory.max`). The
failure only makes sense once you read the OOM report and notice the *cgroup*
constraint — not "the box is out of RAM" but "this service's cap was hit."

**What observability would have caught it faster.** The OOM report names the victim,
its RSS, and the constraint immediately; `memory.events` (`oom_kill`) counts the
kills; alerting on `memory.events` or the OOM log would have made the page
self-diagnosing. The fix lives outside this lesson (raise `memory.max`, or shrink the
working set) — the *diagnosis* is what transfers.
</details>

## How this scenario is graded

`check.sh` verifies the scenario is correctly armed: the **cgroup** OOM reproduces
(`constraint=CONSTRAINT_MEMCG`) and the report names the victim. A later facilitator
layer grades *your* evidence.

## Further reading

Canonical references for deeper exploration:

- [docs.kernel.org — Control Group v2](https://docs.kernel.org/admin-guide/cgroup-v2.html) — the memory controller: `memory.max`, `memory.events`, and cgroup OOM behavior.
- [docs.kernel.org — Concepts overview (memory management)](https://docs.kernel.org/admin-guide/mm/concepts.html) — reclaim and the OOM killer, the machinery behind the report.
