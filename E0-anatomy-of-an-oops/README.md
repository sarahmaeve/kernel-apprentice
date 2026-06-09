# E0 — Anatomy of an oops

> **One event, three views.** The kernel doesn't fail silently — it *reports*, in a
> fixed format it has used for decades: a **WARN** for "this shouldn't happen", a
> **BUG** for "this can't continue", an **oops** for a fault it never saw coming.
> A specimen module *shows* you each shape on demand, the report's fields *explain*
> exactly what died and where, and `faddr2line` lets you *reach in* and turn the
> RIP into the precise source line.

> **Working in the workbench.** Nothing to write or fix — the module fails on
> purpose. (Lesson 05 then ships a crash with a *real* bug behind it; this is where
> you learn to read the report you'll need there.)

## Observe — three failures, three report shapes

```sh
make check LESSON=E0-anatomy-of-an-oops
```

The module creates `/proc/ka-anatomy` and fails to order:

- **`echo warn`** → `WARNING: CPU: … at …/e0_anatomy.c:NN e0_write+0x…` — a loud
  complaint with a full backtrace. Execution **continues**; the writer survives.
- **`echo bug`** → `kernel BUG at …/e0_anatomy.c:NN!` plus `invalid opcode` — an
  explicit assertion. The writing process is **killed**; the kernel survives.
- **`echo oops`** → `BUG: kernel NULL pointer dereference, address: 00…00` — a
  page fault the kernel never expected. Writer **killed**; the kernel survives.

The killed writers exit with `137` — `128 + SIGKILL`, the same number you'll
recognize when a container's process gets OOM-killed (lesson C1).

A **panic** is the fourth rung: nothing survives and the box reboots (here, QEMU
would just exit — the guest boots with `panic=-1`). `panic_on_oops=1` promotes
every oops to a panic; production fleets often set it, preferring a clean reboot
to a wounded kernel limping on.

After each failure the check prints `/proc/sys/kernel/tainted`. Watch it climb:
`4096` (bit 12, **O** — out-of-tree module loaded) → `+512` (bit 9, **W** — a WARN
fired) → `+128` (bit 7, **D** — the kernel has died at least once).

## Read — the oops, field by field

This is the third report, verbatim from the captured log (trimmed where shown):

```
BUG: kernel NULL pointer dereference, address: 0000000000000000
#PF: supervisor write access in kernel mode
#PF: error_code(0x0002) - not-present page
PGD 2181067 P4D 2181067 PUD 2184067 PMD 0
Oops: Oops: 0002 [#2] SMP NOPTI
CPU: 0 UID: 0 PID: 72 Comm: busybox Tainted: G      D W  O      6.18.33 #8 PREEMPT(voluntary)
Tainted: [D]=DIE, [W]=WARN, [O]=OOT_MODULE
RIP: 0010:e0_write.cold+0x16/0x3f [e0_anatomy]
Code: ... 48 8b 04 24 <c7> 00 ad de 00 00 e9 7c ff ff ff ...
RSP: 0018:ffffb174c048fe08 EFLAGS: 00010246
RAX: 0000000000000000 RBX: 0000000000000005 RCX: 0000000000000000
...
Call Trace:
 <TASK>
 proc_reg_write+0x59/0xa0
 vfs_write+0xcf/0x470
 ? count_memcg_events+0x5f/0x180
 ksys_write+0x6b/0xe0
 do_syscall_64+0xb4/0x350
 entry_SYSCALL_64_after_hwframe+0x77/0x7f
 </TASK>
Modules linked in: e0_anatomy(O)
---[ end trace 0000000000000000 ]---
```

- **The headline** — what kind of fault, and the address that triggered it (here
  NULL itself).
- **`error_code(0x0002)` / `Oops: 0002`** — the page-fault handler's verdict,
  bit-coded: bit 0 = caused by a protection violation (0 means the page simply
  wasn't mapped), bit 1 = it was a **write**, bit 2 = from user mode (0 = kernel).
  So `0002` reads: *the kernel wrote to an unmapped address.* (Yes, it prints
  `Oops:` twice — a report tag plus the legacy header.)
- **`[#2]`** — the die counter: the second death this boot (our `BUG()` was `[#1]`).
- **`Tainted: G … D W O`** — context flags that color every report: `G` only GPL
  modules, **`W`** a WARN fired earlier, **`O`** an out-of-tree module is loaded,
  **`D`** the kernel already died once. The kernel even decodes them for you on the
  next line. A tainted report is still readable — but you always ask what tainted
  it *first*.
- **`RIP: 0010:e0_write.cold+0x16/0x3f [e0_anatomy]`** — where it died: the
  instruction pointer as `function+offset/size`, and in which module. The `.cold`
  suffix is the compiler's doing: it parked this unlikely path in a cold
  sub-function. Real-world reports are full of `.cold` / `.isra.0` /
  `.constprop.0` suffixes — they decode the same way. (`0010` is just the kernel
  code segment selector.)
- **`Code:`** — the machine bytes around RIP, the faulting instruction in `<…>`:
  here `c7 00 ad de 00 00` is `movl $0xdead,(%rax)` — our store, with the
  constant visible byte-swapped (`ad de`) — and **`RAX: 0000000000000000`** is the
  NULL it wrote through.
- **`Call Trace:`** — newest frame first: the `write(2)` syscall path that led into
  `e0_write` (`ksys_write` → `vfs_write` → `proc_reg_write` → us). Frames marked
  `?` are addresses found on the stack, not confirmed callers.
- **`Modules linked in: e0_anatomy(O)`** — every loaded module, each with its own
  taint mark. When `O` is in the taint flags, this list is the first place you
  look.
- **`---[ end trace ]---`** — the report is complete; anything after is the next
  event.

One mechanism note: on x86 both `WARN` and `BUG()` compile to the same trap
instruction — `ud2` — and a **bug table** entry tells the handler which it was
(that's why a `BUG()` reports `invalid opcode`). The NULL deref is different:
nobody planned it; the page-fault handler found no mapping at address 0 and
declared an oops.

## Touch — decode the RIP yourself

The report names `e0_write.cold+0x16/0x3f` — offset `0x16` into a `0x3f`-byte
function. Turn that into a source line with the kernel tree's own tool, from
`make shell`:

```sh
cd /work/E0-anatomy-of-an-oops/module
/work/harness/.build/linux-6.18.33/scripts/faddr2line e0_anatomy.ko 'e0_write.cold+0x16'
# e0_write.cold at /work/E0-anatomy-of-an-oops/module/e0_anatomy.c:53
```

Line 53 is the `*nothing = 0xdead;` store — to the line. (Use the RIP from *your*
log; the WARN's `e0_write+0x…` decodes to the `WARN(…)` line too.)

One wrinkle worth keeping: the report said `+0x16/0x3f`, but passing the `/0x3f`
makes `faddr2line` refuse with a *size mismatch*. For module symbols the kernel
estimates size as the gap to the **next** symbol, while the `.ko` records the true
size — when they disagree, drop the `/size` and it resolves. The module is built
with `-g`, so the `.ko` carries the DWARF that `addr2line` needs.
For a crash in the kernel proper you'd point the same script at `vmlinux`;
`scripts/decode_stacktrace.sh` does whole call traces at once. The check runs this
decode at the end (the `decoded:` line) — re-run it by hand so it's yours.

## Verification

Green when the captured log contains all three report shapes (`WARNING:`,
`kernel BUG at`, the NULL-deref oops), the oops RIP names `e0_write`, `faddr2line`
resolves that RIP into `e0_anatomy.c`, and the taint trail shows `W`.

## Why this is lesson E0

Every crash you will ever debug arrives as one of these reports. Lesson 05 (the
driver that oopses) and the Wheel scenarios assume you can already read one; after
this lesson you can — headline, error code, taint, RIP, call trace — and you can
turn any `func+0x…/0x…` into a file and a line.

## Further reading

Canonical references for deeper exploration:

- [docs.kernel.org — Bug hunting](https://docs.kernel.org/admin-guide/bug-hunting.html) — oops decoding end-to-end: locating the bug, `objdump`/gdb tricks, when reports lie.
- [docs.kernel.org — Tainted kernels](https://docs.kernel.org/admin-guide/tainted-kernels.html) — every taint letter and bit, and why "tainted" changes what a report is worth.
