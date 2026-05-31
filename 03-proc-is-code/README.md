# 03 — /proc is code, not files

> **One event, three views.** Reading `/proc/self/status` *looks* like reading a
> file. It isn't. The kernel runs a function and generates those bytes on the spot.
> Here you build your own `/proc` window by hand and watch it produce text live.

> **Working in the workbench.** This lesson builds a loadable module from source in
> this repo (host-editable), then runs `make check` — no kernel edit needed. The
> module is built against the kernel in the build volume.

## The mystery

`cat /proc/self/status` prints memory, state, limits — but there's no file on any
disk holding that. `/proc` is a *virtual* filesystem: each read calls into kernel
code that fabricates the answer right then. It's the kernel wearing a filesystem
costume so that ordinary tools (`cat`, `grep`) can read kernel state.

You're going to **build a `/proc` entry yourself** and prove it's code: read it
twice and watch the numbers change.

## Observe — the tool shows it

In a guest shell, read a couple of virtual files twice in a row:

```sh
cat /proc/uptime ; sleep 1 ; cat /proc/uptime    # the numbers advance
cat /proc/self/status | head                       # live state for THIS process
```

Nothing is stored — the values differ because they're computed at read time.

## Read — the code explains it

`module/proc_window.c` is a complete module. The heart of it is one function and a
small ops table:

```c
static int ka_show(struct seq_file *m, void *v)
{
        seq_printf(m, "kernel-apprentice: hello from a seq_file handler\n");
        seq_printf(m, "reading process: %s (pid %d)\n",
                   current->comm, task_tgid_vnr(current));
        seq_printf(m, "jiffies now:     %lu\n", jiffies);
        return 0;
}
```

`ka_show` writes the file's "contents" with `seq_printf` every time it's read. The
**seq_file** interface handles the buffering, large reads, and seeking for you.
`proc_create("kernel-apprentice", 0444, NULL, &ka_proc_ops)` hangs that handler off
a name under `/proc`. That's the whole window — view two.

## Touch — build the window and look through it

```sh
make check LESSON=03-proc-is-code
```

The harness builds `proc_window.ko`, boots a guest, then the guest's `/init`:

```sh
insmod /proc_window.ko                  # ka_init runs -> /proc/kernel-apprentice appears
cat /proc/kernel-apprentice             # your ka_show() runs and produces this text
cat /proc/kernel-apprentice             # read again — jiffies advanced (it's code!)
rmmod proc_window                       # ka_exit runs -> the entry is gone
```

**PASS** when the captured log shows your seq_file output *and* the creation line —
you built a window across the boundary and read kernel state through it.

## Verification

Green when the serial log contains both:
- `kernel-apprentice: hello from a seq_file handler` — your handler produced output, and
- `kernel-apprentice: /proc/kernel-apprentice created` — the module created the entry.

## Exploration (drive it yourself)

1. **Prove it's code.** The check reads the entry twice; compare the two `jiffies`
   values in the log. A real file wouldn't change between reads.
2. **Add a field.** In `make shell`, edit `module/proc_window.c` to `seq_printf` one
   more line (e.g. the number of CPUs via `num_online_cpus()`), rebuild with
   `make -C module KDIR=...`, reload, and read it back.
3. **Where do the real ones live?** `cat /proc/version`, `/proc/cmdline`,
   `/proc/meminfo` — every one is a `*_show` function somewhere in the tree.

## Why this is lesson three

`/proc` (and `/sys`, and `debugfs`) is how you *read kernel state from userspace* —
the surface most of your debugging starts at. Now you know it's not files: it's
functions you can read, and write, by hand.

## Further reading

Canonical references for deeper exploration:

- [docs.kernel.org — The seq_file Interface](https://docs.kernel.org/filesystems/seq_file.html) — the buffering/iterator API behind `ka_show`.
- [docs.kernel.org — The /proc Filesystem](https://docs.kernel.org/filesystems/proc.html) — what `/proc` is and the conventions its files follow.
