# C2 — KASAN catches you  ·  *optional*

> **⚠ This lesson is OPTIONAL and builds a SECOND kernel.** KASAN is compile-time
> instrumentation, so it needs its own kernel built with `CONFIG_KASAN` — a full
> second kernel compile (minutes) and ~3 GB of extra disk on the build volume. The
> base tutorial kernel is untouched. Nothing else in the curriculum depends on this;
> skip it freely. This mirrors real life: you build a dedicated KASAN kernel to chase
> a memory bug, boot it, read the report, then go back to your normal kernel.

> **Three bugs, escalating.** Once the KASAN kernel exists, the bugs are free —
> they all run on it. C2 walks the three report shapes you'll actually meet:

| Part | Module | Bug | What its report teaches |
|---|---|---|---|
| 1 | `kasan_oob.c` | slab out-of-bounds write | access stack + **Allocated by** stack + the shadow map |
| 2 | `kasan_uaf.c` | use-after-free | adds the **Freed by task** stack — the *three-stack* read |
| 3 | `kasan_df.c`  | double-free | a different category: **double-free or invalid-free** |

## What KASAN is, in one paragraph

KASAN (Kernel Address Sanitizer) is a dynamic memory-error detector — the kernel's
ASan. The compiler inserts a check before every load/store, and the kernel keeps
**shadow memory** (1 byte per 8 bytes) marking which bytes are legal to touch, with
poisoned **redzones** around allocations and a **quarantine** that keeps freed
objects poisoned so reuse is caught. The payoff: an out-of-bounds, use-after-free, or
double-free is caught **at the offending instruction**, instead of as a mysterious
crash far away and later. Generic KASAN is the precise, high-overhead flavor that
syzkaller and CI use — a debug build, never production.

## Build the KASAN kernel (one-time, opt-in)

```sh
make kasan-kernel        # the second kernel build; or let `make check` below do it
```

## Observe — load the modules, KASAN catches them

```sh
make check LESSON=C2-kasan-catches-you
```

The check builds all three modules, boots the KASAN guest, and `insmod`s each. Every
unfixed bug prints a full splat and the check stays **RED**. You fix all three to go
**GREEN**.

## Read — the three report shapes

### Part 1 — out-of-bounds (`kasan_oob.c`)

```
BUG: KASAN: slab-out-of-bounds in kasan_oob_init+0x.../0x... [kasan_oob]
Write of size 1 at addr ffff... by task ...
 <stack of the bad access>          <- the line to fix
Allocated by task ...:
 <stack of the kmalloc>             <- the object you overran
Memory state around the buggy address:
 ... 00 00 fc fc fc ...             <- 00 = in-bounds, fc = redzone you hit
```

### Part 2 — use-after-free (`kasan_uaf.c`) — the meatier one

```
BUG: KASAN: use-after-free in kasan_uaf_init+0x.../0x... [kasan_uaf]
Read of size ... at addr ffff... by task ...
 <stack of the bad access>          <- where you touched freed memory
Allocated by task ...:
 <stack of the kmalloc>
Freed by task ...:                  <- NEW: the kfree that already released it
 <stack of the kfree>
```

The **Freed by task** stack is the whole point: it pairs the bad read with the exact
`kfree` that already released the object — that's how you reason about *lifetime*
bugs.

### Part 3 — double-free (`kasan_df.c`)

```
BUG: KASAN: double-free or invalid-free in kasan_df_init+0x.../0x... [kasan_df]
Free of addr ffff... by task ...
Allocated by task ...:
 <stack of the kmalloc>
Freed by task ...:                  <- where it was ALREADY freed
 <stack of the first kfree>
```

## Touch — fix all three

- **Part 1** — `module/kasan_oob.c`: the loop runs `i = 0 .. LEN` *inclusive*. Make it
  stop at `LEN - 1` (`i < LEN`).
- **Part 2** — `module/kasan_uaf.c`: it's a *lifetime* bug, not a typo. The `pr_info`
  reads the widget after `kfree(w)`. Log it **before** the free (move the line up).
- **Part 3** — `module/kasan_df.c`: the object is freed twice. Free it **once** —
  remove the duplicate `kfree(p)`.

Re-run; with all three fixed, KASAN stays silent and the check goes GREEN.

## Verification

- **RED** while any `BUG: KASAN` naming one of the modules appears in the boot log
  (the splats are printed for you to read).
- **GREEN** once all three modules load with no KASAN report.

Reset to the unsolved skeleton any time:

```sh
make reset LESSON=C2-kasan-catches-you
```

## Why this matters

Out-of-bounds, use-after-free, and double-free are the classic kernel memory-safety
failures — and on a normal kernel they manifest as nondeterministic corruption with a
crash stack that points nowhere near the cause. KASAN turns each into a precise
report. Reading them fluently — access stack, allocation stack, and especially the
**freed-by** stack — is the skill.

## Further reading

- [docs.kernel.org — The Kernel Address Sanitizer (KASAN)](https://docs.kernel.org/dev-tools/kasan.html) — the report format, the three flavors (generic / SW-tags / HW-tags), shadow memory, and the quarantine that catches use-after-free.
- [docs.kernel.org — Concepts overview (memory management)](https://docs.kernel.org/admin-guide/mm/concepts.html) — the slab allocator and kernel memory the redzones guard.
