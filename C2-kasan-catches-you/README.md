# C2 — KASAN catches you  ·  *optional*

> **⚠ This lesson is OPTIONAL and builds a SECOND kernel.** KASAN is compile-time
> instrumentation, so it needs its own kernel built with `CONFIG_KASAN` — a full
> second kernel compile (minutes) and extra disk on the build volume. The base
> tutorial kernel is untouched. Nothing else in the curriculum depends on this; skip
> it freely. This mirrors real life: you build a dedicated KASAN kernel to chase a
> memory bug, boot it, read the report, then go back to your normal kernel.

> **One event, three views.** A tool (KASAN) *shows* you the bad access the instant
> it happens, the report *explains* which access, which object, and which redzone,
> and you *reach in* and fix the off-by-one so KASAN goes silent.

## What KASAN is, in one paragraph

KASAN (Kernel Address Sanitizer) is a dynamic memory-error detector — the kernel's
ASan. The compiler inserts a check before every load/store, and the kernel keeps
**shadow memory** (1 byte per 8 bytes) marking which bytes are legal to touch, with
poisoned **redzones** around allocations and freed objects. The payoff: an
out-of-bounds or use-after-free is caught **at the offending instruction**, instead
of as a mysterious crash far away and later. Generic KASAN is the precise,
high-overhead flavor that syzkaller and CI use — a debug build, never production.

## Build the KASAN kernel (one-time, opt-in)

```sh
make kasan-kernel        # the second kernel build; or let `make check` below do it
```

## Observe — load the module, KASAN catches it

```sh
make check LESSON=C2-kasan-catches-you
```

The shipped `module/kasan_demo.c` has a bug: it writes one byte past a 64-byte
`kmalloc`. On the KASAN kernel that produces a **report** and the check stays RED,
printing the splat for you to read:

```
==================================================================
BUG: KASAN: slab-out-of-bounds in kasan_demo_init+0x.../0x... [kasan_demo]
Write of size 1 at addr ffff... by task ...

 <stack of the bad access>          <- the line to fix

Allocated by task ...:
 <stack of the kmalloc>             <- the object you overran

Memory state around the buggy address:
 ... 00 00 fc fc fc ...             <- 00 = in-bounds, fc = redzone you hit
==================================================================
```

## Read — the report explains it

- **`slab-out-of-bounds` / `Write of size 1`** — a write, one byte, past a slab
  object. (`use-after-free` would mean touching freed memory; `Read of size…` a bad
  read.)
- **First stack** — the *bad access*: `kasan_demo_init` and the offset. This is where
  the fix goes.
- **`Allocated by task`** — where that memory was `kmalloc`'d, so you know *which*
  object you ran past.
- **Shadow map** — `00` bytes are fully addressable; `fc` is a redzone. You wrote
  into the `fc`.

## Touch — fix the off-by-one

Open `module/kasan_demo.c`. The loop runs `i = 0 .. LEN` *inclusive*, so the last
write lands on `buf[LEN]` — out of bounds. Make it stop at `LEN - 1` (i.e. `i < LEN`).
Re-run; KASAN stays silent and the check goes GREEN.

## Verification

- **RED** while `BUG: KASAN` appears in the boot log (and the splat is printed for you).
- **GREEN** once the module loads with no KASAN report.

Reset to the unsolved skeleton any time:

```sh
make reset LESSON=C2-kasan-catches-you
```

## Why this matters

Off-by-one and use-after-free bugs are the classic kernel memory-safety failures —
and on a normal kernel they manifest as nondeterministic corruption with a crash
stack that points nowhere near the cause. KASAN turns that into a precise report.
Reading it fluently — access stack, allocation stack, shadow map — is the skill.

## Further reading

- [docs.kernel.org — The Kernel Address Sanitizer (KASAN)](https://docs.kernel.org/dev-tools/kasan.html) — the report format, the three flavors (generic / SW-tags / HW-tags), and how shadow memory works.
- [docs.kernel.org — Concepts overview (memory management)](https://docs.kernel.org/admin-guide/mm/concepts.html) — the slab allocator and kernel memory the redzones guard.
