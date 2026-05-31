# 07 — A character device with an ioctl

> **CHALLENGE (build it).** You've read the kernel, traced it, instrumented it,
> fixed it. Now build a piece of it: implement a real (if tiny) **character device**
> — `read`, `write`, and an `ioctl` — so a userspace test program passes. This is the
> boundary from lesson 01, seen from the *kernel* side, and the modification
> milestone at full scope.

> **Working in the workbench.** Edit `module/ka_chardev.c` in this repo
> (host-editable), then run `make check` from the host.

## The spec

`module/ka_chardev.c` registers a misc device at `/dev/ka-chardev` backed by a small
in-kernel buffer. Make it behave so that `test.c` passes:

- **write(fd, msg, n)** → store the `n` bytes in the buffer, return `n`.
- **ioctl(fd, KA_GET_LEN, &len)** → set `len` to the number of stored bytes, return 0.
- **read(fd, buf, count)** → return the stored bytes (EOF on a second read).

```sh
make check LESSON=07-char-device-with-ioctl
```

## What you're given

The registration (`misc_register`), the `/dev` node, the `file_operations` table, and
the buffer (`ka_buf` / `ka_len`) are done. Three handlers are stubs marked `TODO`:

```c
static ssize_t ka_read (... )  { /* TODO 1 */ return 0;       }
static ssize_t ka_write(... )  { /* TODO 2 */ return -EINVAL; }
static long    ka_ioctl(... )  { /* TODO 3 */ return -ENOTTY; }
```

As shipped the module loads but rejects writes and answers no ioctls — so the test
fails and the check is **red** until you implement all three.

## Verify

**PASS** when the test prints `TEST PASS` — write stored the bytes, the ioctl
reported the right length, and read returned them unchanged.

## Graduated hints

<details><summary>Hint 1 — ka_write</summary>

Copy from userspace into the buffer and record the length:
```c
size_t n = min_t(size_t, count, BUFSZ);
if (copy_from_user(ka_buf, ubuf, n))
        return -EFAULT;
ka_len = n;
return n;
```
</details>

<details><summary>Hint 2 — ka_read</summary>

The kernel has a helper that copies from a buffer to userspace and honors `*ppos`
(so the second read returns 0):
```c
return simple_read_from_buffer(ubuf, count, ppos, ka_buf, ka_len);
```
</details>

<details><summary>Hint 3 — ka_ioctl</summary>

`arg` is a user pointer to an `int`; write the length into it:
```c
if (cmd == KA_GET_LEN) {
        int len = ka_len;
        if (copy_to_user((int __user *)arg, &len, sizeof(len)))
                return -EFAULT;
        return 0;
}
return -ENOTTY;
```
</details>

## Why this is lesson seven

Lesson 01 walked *through* the syscall door from userspace; here you stand on the
other side and *be* the door — the same `read`/`write`/`ioctl` a real driver
implements. Combined with 05 (fix a driver) and 06 (instrument the kernel), you can
now read, repair, and extend kernel code — the "I changed the actual kernel"
milestone (DESIGN §6).

## Further reading

Canonical references for deeper exploration:

- [docs.kernel.org — Ioctl Numbers](https://docs.kernel.org/userspace-api/ioctl/ioctl-number.html) — how to allocate `_IO`/`_IOR`/`_IOW`/`_IOWR` command numbers like `KA_GET_LEN`.
- [ioctl(2)](https://man7.org/linux/man-pages/man2/ioctl.2.html) — the userspace side of the call `test.c` makes.
