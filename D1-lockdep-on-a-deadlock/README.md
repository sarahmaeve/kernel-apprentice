# D1 — lockdep on a deadlock

> **CHALLENGE (read + fix).** A module runs two maintenance routines, both finish,
> nothing hangs — and the kernel prints a WARNING anyway, because **lockdep** has
> just *proved* that under the right interleaving this code deadlocks. You read a
> deadlock that hasn't happened yet, then fix it. **No TODO markers** — the report
> names everything.

> **Needs the debug kernel.** D1 and D2 boot the lockdep+KCSAN overlay kernel —
> a one-time second build, exactly like C2's KASAN kernel:
> `make debug-kernel`. Edit `module/d1_locks.c` in this repo (host-editable),
> then run `make check` from the host.

## The symptom

```sh
make check LESSON=D1-lockdep-on-a-deadlock
```

`module/d1_locks.c` is a tiny subsystem: a **stats table** and a **cache**, each
with its own mutex, and two routines that need both — `d1_refresh_stats()` and
`d1_drop_caches()`. The module loads, both routines run to completion, the count
prints. And dmesg carries:

```
======================================================
WARNING: possible circular locking dependency detected
------------------------------------------------------
insmod/68 is trying to acquire lock:
 ffffffffc0061148 (d1_stats_lock){+.+.}-{4:4}, at: d1_drop_caches+0x22/0x80 [d1_locks]
but task is already holding lock:
 ffffffffc00610a8 (d1_cache_lock){+.+.}-{4:4}, at: d1_drop_caches+0x14/0x80 [d1_locks]
which lock already depends on the new lock.
...
-> #1 (d1_cache_lock){+.+.}-{4:4}:
       ...
       d1_refresh_stats+0x22/0x70 [d1_locks]
-> #0 (d1_stats_lock){+.+.}-{4:4}:
       ...
       d1_drop_caches+0x22/0x80 [d1_locks]

 Possible unsafe locking scenario:
       CPU0                    CPU1
       ----                    ----
  lock(d1_cache_lock);
                               lock(d1_stats_lock);
                               lock(d1_cache_lock);
  lock(d1_stats_lock);

 *** DEADLOCK ***

1 lock held by insmod/68:
```

## Read the proof

The report is a proof, and every clause matters:

- **"trying to acquire … while already holding"** — the acquisition that closed
  the cycle: `d1_drop_caches` holds the *cache* lock and wants the *stats* lock.
- **"which lock already depends on the new lock"** — lockdep remembers every
  **order** it has ever seen. The `-> #1` chain is the history: `d1_refresh_stats`
  taught it stats → cache. The `-> #0` chain is now: `d1_drop_caches` doing
  cache → stats. That's a cycle — and both chains name their functions.
- **The CPU0/CPU1 box** — the four-line recipe for the real incident: one CPU in
  each routine, each holding its first lock, each waiting forever for the other's.
  Neither ever runs again. That's a deadlock — no oops, no panic, just two tasks
  in `D` forever (the Wheel pages you with exactly that symptom).

The key idea: **lockdep doesn't wait for the deadlock.** It records each lock
*class* ordering and complains the first time the orders form a cycle — one clean,
sequential run of each path is enough. That's why you chase a suspected deadlock
on a debug kernel: production gives you the hang; lockdep gives you the proof
*before* the hang.

## Find + fix

The two routines disagree about which lock comes first. Pick **one order** and
make both comply — lock ordering is a contract across the whole subsystem, not a
per-function choice. (Note lockdep is one-shot: after the first report it turns
itself off for the boot, so fix-and-rerun rather than expecting a second splat.)

## Verify

**PASS** when both routines complete (`d1_locks ran both maintenance routines` in
the log) with **no** circular-dependency warning.

Reset to the unsolved skeleton any time:

```sh
make reset LESSON=D1-lockdep-on-a-deadlock
```

## Graduated hints

<details><summary>Hint 1 — what are the two chains?</summary>

`d1_refresh_stats` takes `stats` → `cache`. `d1_drop_caches` takes `cache` →
`stats`. Each order is fine alone; together they form the cycle the report draws.
</details>

<details><summary>Hint 2 — which function changes?</summary>

Either could — the contract just has to be consistent. Convention: match the
reader (`d1_refresh_stats`), so `d1_drop_caches` should take `stats` first, then
`cache`. You still need *both* locks held while it updates both counters; only the
acquisition order changes.
</details>

<details><summary>Hint 3 — the fix</summary>

```c
static void d1_drop_caches(void)
{
	mutex_lock(&d1_stats_lock);
	mutex_lock(&d1_cache_lock);
	d1_cache_count = 0;
	d1_stat_count++;
	mutex_unlock(&d1_cache_lock);
	mutex_unlock(&d1_stats_lock);
}
```
(Unlock order doesn't matter to lockdep — only acquisition order does.)
</details>

## Why this is lesson D1

ABBA ordering is *the* canonical kernel deadlock, and the production version is
miserable: two tasks wedged in `D`, no report, no crash, just a box that slowly
stops. The debug-kernel workflow you just ran — reproduce on a lockdep kernel,
read the cycle, fix the order — is how it's actually chased. D3 shows you what
the *production* kernel can still tell you; the Wheel pages you with the hang.

## Further reading

Canonical references for deeper exploration:

- [docs.kernel.org — Runtime locking correctness validator](https://docs.kernel.org/locking/lockdep-design.html) — how lockdep classes, orders, and the cycle detection actually work.
- [docs.kernel.org — Generic Mutex Subsystem](https://docs.kernel.org/locking/mutex-design.html) — the lock you've been ordering.
