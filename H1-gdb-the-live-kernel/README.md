# H1 — Step through the live kernel with gdb

> Lesson 04 let you *watch* a function run. Here you **stop time inside the
> kernel**: set a breakpoint on the very `getpid` handler from lesson 01, and when
> the running kernel hits it, freeze — inspect the call stack, registers, the next
> instructions — then let it go. **No rebuild.** The thing kernel-debugging courses
> set up laboriously with kgdb, we get almost for free, because the guest is a QEMU VM.

> **Working in the workbench.** No module, no kernel edit. You attach `gdb` to the
> running guest.

## The trick: QEMU is already a debugger

QEMU exposes a **gdb stub**. Launch it with `-gdb tcp::1234` (or `-s`) and `-S`
(start with the CPU frozen), point `gdb vmlinux` at it, and you're debugging the
kernel like any other program — breakpoints, backtraces, registers, single-step.

One catch: boot with **`nokaslr`** so the kernel's runtime addresses match the
symbols in `vmlinux` (otherwise KASLR shifts everything and your breakpoints miss).

## Touch — break into the running kernel

```sh
make check LESSON=H1-gdb-the-live-kernel
```

The harness boots the guest frozen with a stub, attaches gdb, breaks on
`__do_sys_getpid`, continues until a `getpid()` hits it, and prints the stack:

```
Breakpoint 1, __x64_sys_getpid ()    # the getpid syscall handler, frozen mid-call
#0  __x64_sys_getpid ()
#1  do_syscall_64 ()                 # who called it
```

You break on `__do_sys_getpid` (the body lesson 04 traced), but gdb reports the
address as `__x64_sys_getpid`: for a zero-argument syscall the `SYSCALL_DEFINE0`
wrappers collapse to one address, and each tool picks a different alias for it
(kallsyms for ftrace, ELF symbols for gdb). Same code, different name.

**PASS** when gdb actually *stops* in the getpid handler on the live kernel — you
froze the kernel mid-syscall and looked around, the deepest "reach in" yet.

## Do it yourself (interactive)

Two shells from `make shell`:

```sh
# shell 1 — boot the guest frozen, stub on :1234
harness/run-qemu.sh ... # (or run qemu-system-x86_64 -kernel … -initrd … \
  #  -append "console=ttyS0 nokaslr" -S -gdb tcp::1234 -nographic)

# shell 2 — drive it
gdb harness/.build/linux-6.18.33/vmlinux
(gdb) target remote :1234
(gdb) break __do_sys_getpid
(gdb) continue
(gdb) backtrace          # the path from userspace into the handler
(gdb) info registers
(gdb) x/4i $pc           # the instructions about to execute
(gdb) finish             # run until this function returns
(gdb) continue
```

## Why this is the differentiator

The Babka deck spends a whole section on kgdb: a serial console, `kgdboc=ttyS0`,
`echo g > /proc/sysrq-trigger` to break in. All real, all fiddly. Because our guest
is QEMU, we skip every bit of it — the gdb stub is built into the emulator. *That's*
something a lecture or a video can't easily let you do; you can, right now.

## Note — source lines and locals

This kernel is built **without** `CONFIG_DEBUG_INFO`, so gdb shows function names and
offsets but not source lines or local variable names. Turning on debug info upgrades
every gdb session to full source level (`list`, `info locals`, `kernel/sys.c:NN`) —
we enable it when we build the oops/crash module, and these same commands light up.

## Why this is in the toolkit

When you *can't* recompile a box but *can* attach a debugger (a VM, a board with a
JTAG/gdb stub), this is how you find out what the kernel is actually doing — the
last resort that still works when printk and tracing aren't enough.

## Further reading

Canonical references for deeper exploration:

- [docs.kernel.org — Debugging kernel and modules via gdb](https://docs.kernel.org/process/debugging/gdb-kernel-debugging.html) — the QEMU-gdbstub workflow plus the `lx-` helper commands (`lx-dmesg`, `lx-symbols`, …).
- [docs.kernel.org — Using kgdb, kdb and the kernel debugger internals](https://docs.kernel.org/process/debugging/kgdb.html) — the on-hardware version, for when there's no QEMU.
