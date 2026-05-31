# 02 — printk and the ring buffer

> **One event, three views.** In lesson 1 you made *existing* kernel code speak.
> Here you build the speaking mechanism yourself — a loadable module — and watch
> where its words go: the kernel's ring buffer, filtered by log level on the way
> to the console.

## The mystery

`dmesg` prints kernel messages. But where do they come from, where do they *live*,
and why do some show up on the console while others only appear when you ask? The
answer is `printk` and the **kernel log ring buffer** — and the thing you build in
this lesson *is itself an observability mechanism*. Every diagnosis later in this
course reads this buffer.

Unlike lesson 1, this needs no kernel rebuild. A **loadable module** (`.ko`) is
the gentle, fast loop: compile it against the kernel tree, `insmod` it, watch it
talk, `rmmod` it. (DESIGN §8: *modules to start*.)

## Observe — the tool shows it

In a guest shell (`make shell`, then boot the base guest), run `dmesg -w` in one
window and load a module in another. Lines appear the instant they're emitted.
Each carries a **log level**, 0 (`KERN_EMERG`) to 7 (`KERN_DEBUG`).

## Read — the code explains it

`module/hello.c` emits exactly one line at each level:

```c
static int __init hello_init(void)
{
        pr_emerg ("kernel-apprentice: hello at EMERG (0)\n");
        ...
        pr_info  ("kernel-apprentice: hello at INFO  (6)\n");
        pr_debug ("kernel-apprentice: hello at DEBUG (7)\n");  /* see exploration */
        return 0;
}
module_init(hello_init);
module_exit(hello_exit);
```

`pr_emerg`/`pr_info`/… are thin wrappers over `printk` that stamp the level.
`module_init`/`module_exit` register the load/unload hooks. Read the whole file —
it's short, and it's a complete, real kernel module.

## Touch — load it and watch

```sh
make check LESSON=02-printk-and-ring-buffer
```

The harness builds `hello.ko` against the pinned kernel tree, boots a guest, then
the guest's `/init`:

```sh
insmod /hello.ko          # hello_init runs → 8 printk lines hit the ring buffer
dmesg | grep kernel-apprentice
rmmod hello               # hello_exit runs → "goodbye"
```

**PASS** when the `INFO` line and the `goodbye` line are in the captured log: you
built a kernel module, loaded it, made it speak, and unloaded it cleanly.

## Verification

Green when the serial log contains:
- `kernel-apprentice: hello at INFO` — your module emitted into the ring buffer, and
- `kernel-apprentice: goodbye` — it unloaded cleanly (the `__exit` path ran).

## Exploration (drive it yourself)

1. **The console filter.** `dmesg` shows *all* eight... but did all eight reach the
   serial console as the module loaded? The console only prints messages more
   urgent than `console_loglevel`. Inspect and lower it:
   ```sh
   cat /proc/sys/kernel/printk        # current console_loglevel is the first number
   echo 1 > /proc/sys/kernel/printk   # now only EMERG/ALERT reach the console
   ```
   Re-load the module: fewer lines on the console, but `dmesg` still has them all.
   The **ring buffer holds everything; the console is a filtered view.** This is
   why you `dmesg` after the fact instead of trusting what scrolled past.
2. **The debug line.** `pr_debug` (level 7) is compiled out / silent unless dynamic
   debug is enabled for it. Why might a kernel be built that way? When would you
   want it on in production?

## Why this is lesson two

The ring buffer is the kernel's own running narration. Lessons from here on —
OOM reports, oopses, tracepoints — are all *read out of this buffer*. You just
built the thing that writes to it.
