# D3 — Lockups & hung tasks

> **One event, three views.** When a CPU stops scheduling or a task stops running,
> the kernel doesn't just suffer — **it tells you**, unprompted. Two detectors ship
> on (and are enabled by) production distro kernels: the **soft-lockup watchdog**
> (a CPU hasn't scheduled in N seconds) and **khungtaskd** (a task has been in
> uninterruptible `D` sleep for N seconds). A specimen module stalls both ways on
> purpose; the reports *show* it, their fields *explain* who and where, and the
> thresholds you tune are the *reach in* — the same knobs production fleets set.

> **Working in the workbench.** Nothing to fix — the stalls are deliberate. Runs
> on the base kernel, but Module D added the two detectors to its config: if the
> check says so, run `make kernel` once to pick them up.

## Observe — two stalls, two detectors

```sh
make check LESSON=D3-lockups-and-hung-tasks
```

The module creates `/proc/d3-stall`; the check lowers both detector thresholds,
then stalls to order:

- **`echo spin`** → hogs one CPU for 6 seconds with preemption disabled
  (interrupts still on). The **watchdog** — a per-CPU timer that checks "has this
  CPU scheduled lately?" — fires:
  `watchdog: BUG: soft lockup - CPU#N stuck for Xs!`
- **`echo hang`** → parks a kthread (`d3-hung`) in `TASK_UNINTERRUPTIBLE`.
  **khungtaskd** wakes periodically, scans for tasks stuck in `D`, and reports:
  `INFO: task d3-hung:NN blocked for more than 3 seconds.`

Both are **reports, not crashes** — the spin ends and the CPU recovers; the box
keeps running. (A *hard* lockup — interrupts off too — has its own NMI-based
detector; our QEMU/TCG guest doesn't model the NMI watchdog, so we teach it in
prose: same idea, one rung worse.)

## Read — the two report shapes

The soft lockup names the CPU, the guilty code (RIP into `d3_stall`), and taints
the kernel with `L`:

```
watchdog: BUG: soft lockup - CPU#1 stuck for 6s! [busybox:67]
Modules linked in: d3_stall(O)
...
RIP: 0010:d3_write.cold+0x3d/0x74 [d3_stall]
Call Trace: ... proc_reg_write ... vfs_write ...
```

The comm in brackets (`busybox:67`) is whoever was *on* the CPU — the writer
that triggered the spin — and the RIP names the spinning code (`.cold` is the
compiler's unlikely-path split; E0 taught you that suffix).

khungtaskd names the task, how long it's been stuck, and the stack that parked it
— everything H2 taught you to pull by hand with sysrq `w`, delivered unprompted:

```
INFO: task d3-hung:70 blocked for more than 3 seconds.
      Tainted: ...
"echo 0 > /proc/sys/kernel/hung_task_timeout_secs" disables this message.
task:d3-hung         state:D stack:15000 pid:70    tgid:70    ppid:2 ...
Call Trace: ... d3_hung_fn+0x42/0x4c [d3_stall] ...
```

- **soft lockup = a CPU problem** (something *running* won't let go);
  **hung task = a task problem** (something *sleeping* won't wake). Different
  detector, different fix direction — the first thing to read off the page.
- The hung-task report is your khungtaskd vocabulary for the Wheel: in a real
  incident this line is often the *only* unprompted evidence.

## Touch — the knobs production tunes

The check sets them in the guest; these are real fleet-tuning knobs, not lesson
props:

```sh
echo 2 > /proc/sys/kernel/watchdog_thresh           # soft lockup at ~2x this
echo 3 > /proc/sys/kernel/hung_task_timeout_secs    # khungtaskd's patience
# also real: kernel.softlockup_panic / kernel.hung_task_panic = 1 — promote
# either report to a panic (then kdump gives you a corpse — lesson E1).
```

## Verification

Green when the captured log shows the soft-lockup report with a RIP inside
`d3_stall`, the spin *completing* (it's a report, not a crash), and the
khungtaskd report naming `d3-hung` with `d3_hung_fn` in its stack.

## Why this is lesson D3

These two reports appear in real production dmesg without anyone asking — on
oversubscribed cloud VMs, soft lockups are practically weather. Knowing which
detector is talking and what its threshold means turns a scary page into a
located problem. H2 was you *asking* a wedged box for state; D3 is the box
*volunteering* it; the Wheel is the incident where you need both.

## Further reading

Canonical references for deeper exploration:

- [docs.kernel.org — Softlockup detector and hardlockup detector](https://docs.kernel.org/admin-guide/lockup-watchdogs.html) — both watchdogs, their thresholds, and the panic knobs.
- [docs.kernel.org — Documentation for /proc/sys/kernel/](https://docs.kernel.org/admin-guide/sysctl/kernel.html) — `watchdog_thresh`, `hung_task_*`, `softlockup_panic`: every knob this lesson touched.
