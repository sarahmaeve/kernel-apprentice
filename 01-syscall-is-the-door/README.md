# 01 — The syscall is the door

> **One event, three views.** A single ordinary moment — your program asks the
> kernel "what's my PID?" — seen three ways: a tool *shows* it, kernel C
> *explains* it, and your own `printk` lets you *reach in* and confirm the exact
> line ran.

## The mystery

Every interaction between your software and the kernel goes through one narrow
door: the **syscall**. You call a libc function, it traps into the kernel, a
specific C function runs, and you get an answer back. That door is where almost
every "novel software behaves badly on the real box" problem lives.

You're going to watch a program walk through that door, find the exact kernel
function on the other side, and then **prove** it ran — by making it speak.

The challenge: *make a specific line of kernel code announce itself in `dmesg`,
firing exactly when (and only when) our test program calls `getpid()`.*

There's a small program in this directory, `door.c`. All it does is ask the
kernel for its PID and print it:

```c
pid_t p = getpid();
printf("door: my pid is %d\n", (int)p);
```

## Observe — the tool shows it

`check.sh` runs `door` under `strace` inside the guest. You'll see the boundary
crossing in the output:

```
getpid()  = 42
```

`strace` sits at the door and logs everyone who walks through. That's view one.

## Read — the code explains it

On the kernel side, `getpid()` is handled by a tiny function. In the pinned
source (`harness/.build/linux-6.18.33/`), open **`kernel/sys.c`** and find:

```c
SYSCALL_DEFINE0(getpid)
{
        return task_tgid_vnr(current);
}
```

`SYSCALL_DEFINE0` is the macro that *defines a syscall taking 0 arguments*.
`current` is the running task; `task_tgid_vnr` returns its PID as seen from the
task's namespace. That's the whole door for `getpid`. That's view two.

## Touch — your printk confirms it

Now reach in. Add a `printk` to that handler so it announces itself — but only for
*our* process, so we don't drown the log (every program in the system calls
`getpid`; a blind printk here would flood — a lesson in itself, and the reason
later lessons reach for dynamic tracing instead).

Edit `SYSCALL_DEFINE0(getpid)` in `kernel/sys.c` to read:

```c
SYSCALL_DEFINE0(getpid)
{
        if (!strcmp(current->comm, "door"))
                pr_info("kernel-apprentice: getpid by %s pid=%d\n",
                        current->comm, task_tgid_vnr(current));
        return task_tgid_vnr(current);
}
```

Then from the repo root:

```sh
make check LESSON=01-syscall-is-the-door
```

The harness does an **incremental** rebuild (seconds), boots the guest, runs
`door` under `strace`, and greps the kernel log. **PASS** when both views line up:
`strace` shows `getpid()` *and* your printk shows the same PID. That's view three —
you've confirmed *that exact line ran*.

## Verification

`check.sh` is green only when the serial log contains both:
- `getpid(` — the boundary, observed by strace, and
- `kernel-apprentice: getpid by door` — your line of kernel C, reached and fired.

Compare the PID in the `strace` line with `pid=` in your printk. Same number. The
door, the function behind it, and proof it ran — one event, three views.

## Graduated hints

<details><summary>Hint 1 — where does getpid live?</summary>

`grep -rn "SYSCALL_DEFINE0(getpid)" harness/.build/linux-6.18.33/kernel/`
</details>

<details><summary>Hint 2 — why guard on the process name?</summary>

Every process calls `getpid` constantly. An unconditional `printk` floods the
ring buffer and the console. `current->comm` is the current task's command name
(`"door"` for our program), so guarding on it keeps the log clean.
</details>

<details><summary>Hint 3 — the exact edit</summary>

In `kernel/sys.c`, replace the body of `SYSCALL_DEFINE0(getpid)` with the guarded
`pr_info` shown in the **Touch** section above. `strcmp`, `current`, `pr_info`,
and `task_tgid_vnr` are all already available in that file — no new includes.
</details>

## Why this is lesson one

If you can find the function behind a syscall and prove it ran, you can do that
for *any* boundary crossing your software makes. Everything after this — task
states, OOM, dropped packets — is the same move against a bigger door.
