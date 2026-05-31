# Wheel of Misfortune — "Works on my laptop"

> **Live fire, symptom-first.** You're paged with what production shows you and
> nothing more. The guest is genuinely broken. Drive real tools; **score on the
> evidence you point at, not on guessing the cause** (DESIGN §7).

---

## 📟 The page

> A new service, `svc`, refuses to start on the prod-shaped box. It dies during
> startup with a cryptic message and a non-zero exit. The developer swears
> **"it works on my laptop"** — and it does, every time, on theirs.
>
> Same binary. Same inputs. Different box. Find out *what the kernel is telling
> the service*, and point at the evidence.

That's all you get. Don't read ahead to the post-mortem until you've driven it.

## Run the scenario

```sh
make check LESSON=wheel/works-on-my-laptop
```

This boots the broken guest and runs `svc` under `strace` so you can watch the
failure happen. (The same `svc` source is in this directory — but the bug isn't
*in* the source; it's in the environment the kernel hands it.)

## Your job

1. **Reproduce & read the symptom.** What exactly does `svc` print? What's its
   exit code?
2. **Go to the boundary.** `strace` is already capturing the run. Which syscall
   fails, and with which **errno**? An errno is the kernel telling you precisely
   why the door wouldn't open.
3. **Corroborate from `/proc`.** The errno points at a *limit*. Where does the
   kernel expose the limits a process is actually running under? (Hint: it's a
   file per process.) Find the number that's too small.
4. **Point at the evidence.** State it as: *"`svc` fails because syscall X returns
   errno Y; `/proc/<pid>/limits` shows limit Z = N, lower than it needs."* That —
   not naming a fix — is the win.

## Graduated hints

<details><summary>Hint 1 — what does the symptom look like?</summary>

`svc` warms a pool of file descriptors on startup. The failure message is about
that warmup. Read it literally.
</details>

<details><summary>Hint 2 — which syscall, which errno?</summary>

In the `strace` output, find the first call that returns `-1`. The errno is
`EMFILE` — *"Too many open files."* That's a per-process resource ceiling, not a
bug in the code.
</details>

<details><summary>Hint 3 — where the kernel shows the ceiling</summary>

```sh
cat /proc/self/limits | grep 'open files'
```
The **soft limit** on open files (`RLIMIT_NOFILE`) is far lower here than on the
laptop. The service needs more descriptors than the box allows it.
</details>

## 🧾 Post-mortem (read after you've driven it)

**Ground truth.** The guest boots with `RLIMIT_NOFILE` set deliberately low
(`ulimit -n 64`). `svc` tries to open a pool of 256 descriptors; around the 64th,
`open()` returns `-1 EMFILE`. Nothing is wrong with the binary — the *environment*
differs from the laptop, which ships a generous default limit.

**Why it's the archetype.** This is the motivating scenario in miniature
(DESIGN §7): novel software meets a production-shaped box whose kernel-enforced
limits differ from a dev laptop, and the failure only makes sense once you read
the errno at the syscall boundary and corroborate it in `/proc`. No crash, no
kernel bug — just the kernel quietly enforcing a policy nobody checked.

**What observability would have caught it faster.** A single `strace` at startup
shows `openat(...) = -1 EMFILE` immediately; `/proc/<pid>/limits` confirms the
ceiling. Logging the errno (not just "startup failed") would have made the page
self-diagnosing. The fix lives outside this lesson (raise the limit via
`LimitNOFILE=`, `ulimit`, or `/etc/security/limits.conf`) — but the *diagnosis*,
the part that transfers to every future incident, is what you just did.

## How this scenario is graded

`check.sh` verifies the scenario is correctly armed: the run reproduces the
`EMFILE` failure **and** the low limit is visible in `/proc`. (A later facilitator
layer — graduated hints or an LLM on-call lead — will grade *your* evidence; for
now, the check confirms the box is broken the way the page describes.)
