# Wheel of Misfortune — "The process that won't die"

> **Live fire, symptom-first.** The box is genuinely broken — a service is frozen
> and *nothing can kill it*. Drive real tools; **score on the evidence you point
> at**, not on a guess (DESIGN §7).

---

## 📟 The page

> The ticket service, `ticketd`, has **stopped handling requests**. Its log ends
> mid-request and never resumes. The supervisor tried a restart; the old process
> **won't exit** — `kill -9` does *nothing*. Load average is climbing although the
> CPUs are idle. The binary is unchanged; it ran fine until the last deploy added
> the vendor's journaling driver. Find out **where it's stuck, and why kill -9
> can't touch it**.

Don't read the post-mortem until you've driven it.

## Run the scenario

```sh
make check LESSON=wheel/the-process-that-wont-die
```

## Your job

1. **Reproduce & read the symptom.** `ticketd: journaling ticket 1` … and nothing.
   No error, no exit, no crash. `kill -9` returns success and changes nothing.
2. **Ask what state the task is in.** `grep State /proc/<pid>/status` — the answer
   is the whole incident: `D (disk sleep)`, *uninterruptible*. Signals — SIGKILL
   included — stay pending (`SigPnd`) until the task next runs, which is exactly
   what it won't do.
3. **Ask *where* it's stuck.** `cat /proc/<pid>/stack` (H2's move). The top frame
   is `vjournal_write` — wedged *inside the vendor driver*. (The stack file
   filters the lock/scheduler plumbing; khungtaskd's dmesg trace shows the full
   `__mutex_lock` path.)
4. **Ask who else.** `dmesg` — khungtaskd (D3's detector) has been reporting
   unprompted: *two* tasks blocked, `ticketd` **and** the driver's own
   `vjournal-compact` thread. Better: 6.18's detector names the relationship
   outright —
   `INFO: task ticketd:68 is blocked on a mutex likely owned by task vjournal-compac:67.`
   (Note the 15-character comm truncation — a real-log reading skill of its own.)
5. **Point at the evidence.** State it as: *"`ticketd` is in uninterruptible sleep
   inside `vjournal_write`, waiting on the journal mutex; the holder,
   `vjournal-compact`, is itself wedged in `D` — so the lock never releases and
   SIGKILL can never be delivered."*

## Why kill -9 cannot work

`SIGKILL` doesn't destroy a process; it's delivered the next time the task runs.
A task in `TASK_UNINTERRUPTIBLE` is not runnable and doesn't process signals —
that's the contract (normally held for microseconds around I/O). A task that
*stays* in D is beyond the reach of userspace entirely: the only ways out are the
resource it's waiting for appearing, or a reboot. That's also why **load average
climbs while CPUs idle**: Linux counts D-state tasks into loadavg.

## Graduated hints

<details><summary>Hint 1 — the state</summary>

```
$ grep -E '^(Name|State|SigPnd)' /proc/68/status
Name:   ticketd
State:  D (disk sleep)
SigPnd: 0000000000000100
```
`D` = uninterruptible, and that pending-signal bit is **signal 9** — the SIGKILL
that landed and will never be delivered.
</details>

<details><summary>Hint 2 — the place</summary>

```
$ cat /proc/68/stack
[<0>] vjournal_write+0x19/0x40 [vjournal]
[<0>] proc_reg_write+0x59/0xa0
[<0>] vfs_write+0xcf/0x470
[<0>] ksys_write+0x6b/0xe0
[<0>] do_syscall_64+0xb4/0x350
```
Read bottom-up: the `write(2)` syscall path, ending in the vendor module. The
stack file filters lock/scheduler internals — khungtaskd's own dmesg trace shows
the `__mutex_lock` frames if you want them.
</details>

<details><summary>Hint 3 — the kernel already told you</summary>

`dmesg | grep "blocked for more than"` — khungtaskd reported both `ticketd` and
`vjournal-compact`, and then named the relationship:

```
INFO: task ticketd:68 is blocked on a mutex likely owned by task vjournal-compac:67.
```

Two D-state tasks, one lock: the holder is the root cause, the service is
collateral.
</details>

## 🧾 Post-mortem (read after you've driven it)

<details><summary>open after you've driven it — ground truth + the lesson</summary>

**Ground truth.** The vendor driver's compaction thread takes the journal mutex
and then waits forever for "device I/O" that never completes (`vjournal.c` — a
stand-in for a dead device, a lost interrupt, or a firmware hang). `ticketd`'s
next `write(2)` enters `vjournal_write`, queues on the mutex in uninterruptible
sleep, and is now unkillable. Nothing is wrong with `ticketd` — the **vendor
module wedged while holding a lock the service needs**.

**Why it's the archetype.** "Unkillable process + climbing load + idle CPUs" is
one of the classic production pages, and the cause is almost always a D-state
wait on a dead resource — NFS server gone, dying disk under `fsync`, wedged
vendor driver. The diagnosis is mechanical once you know the moves: state, stack,
khungtaskd — who's stuck, where, and who's *holding* what they wait for.

**What observability would have caught it faster.** khungtaskd had already named
both tasks *and the mutex owner* before anyone looked (`blocked on a mutex likely
owned by task vjournal-compac:67`) — alerting on `INFO: task … blocked for more
than` (or `kernel.hung_task_panic=1` + kdump in stricter fleets) makes this page
self-diagnosing. Lesson D1 shows the *lab* version of the lock analysis; E1
(planned) turns the strict-fleet path into a post-mortem you can walk.
</details>

## How this scenario is graded

`check.sh` verifies the scenario is correctly armed: the service freezes
mid-request, sits in `D`, survives `kill -9`, its stack names the vendor module,
and khungtaskd reports the hang. A later facilitator layer grades *your*
evidence.

## Further reading

Canonical references for deeper exploration:

- [docs.kernel.org — Softlockup detector and hardlockup detector](https://docs.kernel.org/admin-guide/lockup-watchdogs.html) — the detector family around khungtaskd.
- [docs.kernel.org — Generic Mutex Subsystem](https://docs.kernel.org/locking/mutex-design.html) — why mutex waiters sleep uninterruptibly.
