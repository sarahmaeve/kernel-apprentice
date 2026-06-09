# 05 — The driver that oopses

> **CHALLENGE (read + fix).** A module ships with a bug. Writing to `/proc/ka-oops`
> crashes the kernel — an **oops**. Your job: trigger it, *read* the oops, trace it
> back to the buggy line, find what's wrong, and fix it. **No TODO markers** — you
> diagnose, like you would a third-party driver that misbehaves on the real box.

> **Working in the workbench.** Edit `module/oops_driver.c` in this repo
> (host-editable), then run `make check` from the host.

## The symptom

The module creates `/proc/ka-oops`. Write to it and the kernel oopses with a **NULL
pointer dereference**. The *writing process* is killed, but the kernel survives — an
oops isn't a panic. `make check` does this for you and shows the trace:

```sh
make check LESSON=05-the-driver-that-oopses
```

## Read the oops

You'll see something like this in the captured log:

```
BUG: kernel NULL pointer dereference, address: 0000000000000000
...
RIP: 0010:ka_write+0x.../0x...  [oops_driver]
Call Trace:
 ka_write              [oops_driver]
 proc_reg_write
 vfs_write
 ksys_write
```

The **RIP** and the top of the **Call Trace** name the function that crashed:
`ka_write`, in this module. `address: 0000...0000` says it dereferenced **NULL**.
(You dissected this exact format in lesson E0 — apply it.) Open `ka_write` and ask:
*what does it write through, and is that pointer valid?*

## Find + fix

Trace it back: `ka_write` copies the user data into a local buffer (fine), then
`memcpy`s it into `state->buf`. Where is `state->buf` set? Look at `ka_init` — it
allocates `state`, but **never allocates `state->buf`**, so it's `NULL`. That's the
deref. Fix it: give the buffer real memory.

## Verify

**PASS** when the write completes with **no oops** — the log shows
`kernel-apprentice: ka-oops stored N bytes`. You read a crash, found the bug, and
fixed it.

## Graduated hints

<details><summary>Hint 1 — where does it crash?</summary>

The `RIP` / first Call Trace frame is `ka_write`. The faulting `address:` is `0`, so
something in `ka_write` dereferences a NULL pointer.
</details>

<details><summary>Hint 2 — what's NULL?</summary>

`ka_write` writes into `state->buf` via `memcpy`. `ka_init` does
`state = kzalloc(...)` (which zeroes it), but never sets `state->buf` — so it stays
`NULL`.
</details>

<details><summary>Hint 3 — the fix</summary>

Allocate the buffer in `ka_init`, after `state` is allocated:

```c
state->buf = kmalloc(BUFSZ, GFP_KERNEL);
if (!state->buf) {
        kfree(state);
        return -ENOMEM;
}
```
(`ka_exit` already `kfree`s `state->buf`, so no leak.)
</details>

## Why this is lesson five

Decoding an oops — `RIP` → function → the faulting line — is *the* core skill when
third-party software ships a driver that interacts badly with the kernel (the
motivating scenario, DESIGN §1). You just did it on a controlled crash; the Wheel's
"driver that oopses" does it under incident pressure.

## Further reading

Canonical references for deeper exploration:

- [docs.kernel.org — Bug hunting](https://docs.kernel.org/admin-guide/bug-hunting.html) — reading an oops, finding the bug's location, taint flags, `objdump`/gdb decoding.
- [docs.kernel.org — Debugging kernel and modules via gdb](https://docs.kernel.org/process/debugging/gdb-kernel-debugging.html) — turn a `RIP` address into a source line (pairs with lesson H1).
