# D2 — KCSAN finds a race

> **CHALLENGE (read + fix).** Two workers process 200,000 events each and count
> them in a shared total. Every event is counted exactly once — and the total
> still comes up short, *differently every run*. That's a **data race**: the bug
> class that produces no crash, no error, just quietly wrong numbers. **KCSAN**
> (the Kernel Concurrency Sanitizer) catches it in the act and shows you both
> sides. **No TODO markers** — the report names the function.

> **Needs the debug kernel.** Same overlay as D1 (`make debug-kernel`, one-time).
> Edit `module/d2_race.c` in this repo (host-editable), then `make check` from
> the host.

## The symptom

```sh
make check LESSON=D2-kcsan-finds-a-race
```

```
BUG: KCSAN: data-race in d2_count_event [d2_race] / d2_count_event [d2_race]

write to 0xffffffffc03246c0 of 8 bytes by task 70 on cpu 1:
 d2_count_event+0x29/0x40 [d2_race]
 d2_worker+0x29/0x40 [d2_race]
 kthread+0x1b5/0x330
 ...
read to 0xffffffffc03246c0 of 8 bytes by task 69 on cpu 0:
 d2_count_event+0x12/0x40 [d2_race]
 d2_worker+0x29/0x40 [d2_race]
 ...
kernel-apprentice: d2_race counted 347162 of 400000 events
```

(That run lost **52,838 events** — and the next run will lose a different number.)

## Read the report

- **Two stacks, two CPUs, one address.** That's the entire definition of a data
  race: concurrent access to the same memory, at least one a write, no ordering
  between them. KCSAN catches it by planting a **watchpoint** on a sampled access
  and stalling briefly — if another CPU touches the same address during the stall,
  both parties are caught red-handed.
- **Look closer: it's the same line, caught mid-split.** One stack is the *read*
  at `d2_count_event+0x12`, the other the *write* at `+0x29` — that's the single
  `d2_total++` torn open into its load and store, photographed mid-interleave.
- **Why the count is short.** `d2_total++` is not one operation — it's a
  read-modify-write: load `N`, add 1, store `N+1`. Two CPUs interleave: both load
  `N`, both store `N+1` — two events happened, the counter moved once. Multiply by
  a sampling of 400,000 increments and the total drifts low by a different amount
  every run.
- **Why this bug is miserable in production.** Nothing crashes. No report appears
  (production kernels don't run KCSAN). You just have metrics that don't add up,
  intermittently, worse under load. The fix is trivial *once you believe the
  diagnosis* — which is what the sanitizer is for.

## Find + fix

Make the increment a single indivisible operation. The kernel's tool for "a
counter shared across CPUs" is `atomic_long_t` and friends — and note the check
is not satisfiable by *silencing* KCSAN (e.g. wrapping the access in
`data_race()`): it independently requires the count to be **exact**.

## Verify

**PASS** when the log shows `counted 400000 of 400000 events` and **no**
`BUG: KCSAN: data-race`.

Reset to the unsolved skeleton any time:

```sh
make reset LESSON=D2-kcsan-finds-a-race
```

## Graduated hints

<details><summary>Hint 1 — where is the race?</summary>

The report names `d2_count_event` twice — both racing parties are the same line:
`d2_total++`, executed concurrently by `d2-worker-a` and `d2-worker-b`.
</details>

<details><summary>Hint 2 — what's the right primitive?</summary>

A plain `long` can't be safely incremented from two CPUs. The kernel's atomic
counter types (`atomic_long_t`, `atomic_long_inc`, `atomic_long_read`) make the
read-modify-write indivisible — and KCSAN knows marked atomic operations are
intentional, so it stops reporting them.
</details>

<details><summary>Hint 3 — the fix</summary>

```c
static atomic_long_t d2_total = ATOMIC_LONG_INIT(0);

static noinline void d2_count_event(void)
{
	atomic_long_inc(&d2_total);
}
```
…and print it with `atomic_long_read(&d2_total)` in `d2_init`.
</details>

## Why this is lesson D2

Lost updates from unsynchronized counters are among the most common real
concurrency bugs in driver and module code — and the least visible: wrong
numbers, no crash. D1's lockdep proved a *deadlock* before it happened; KCSAN
proves a *race* while it happens. Same workflow both times: reproduce on the
debug kernel, read the report, fix the code, rerun until silent.

## Further reading

Canonical references for deeper exploration:

- [docs.kernel.org — The Kernel Concurrency Sanitizer (KCSAN)](https://docs.kernel.org/dev-tools/kcsan.html) — watchpoints, what counts as a race, and the `data_race()`/`READ_ONCE()` vocabulary.
- [docs.kernel.org — Semantics and Behavior of Atomic Types](https://docs.kernel.org/core-api/wrappers/atomic_t.html) — the atomic counter API you used for the fix.
