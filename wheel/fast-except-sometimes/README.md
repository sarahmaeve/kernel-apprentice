# Wheel of Misfortune — Fast except sometimes

> **Live fire.** A symptom and a box. No TODO, no skeleton — you diagnose it with the
> tools, then point at the evidence. This is the capstone of the tracing track: B1–B4
> were drills; this is the call.

## 📟 The page

> `slowsvc` is serving fine — median latency is **~2 µs**. But the dashboard p99 is
> **20 ms**, ten-thousand times worse, and a few requests an hour just *hang*. CPU is
> idle, memory is fine, no errors in the log. Find out why some requests are slow.

The "service" is `/proc/slowsvc`; each read is a request.

## Run the scenario

```sh
make check LESSON=wheel/fast-except-sometimes
```

It loads the service, sends 10 requests under a tracer, and shows you the evidence.

## Your job

Most requests are instant; a minority are catastrophically slow, and the averages hide
it. **Find which code path the slow requests take, and why** — using the tracing tools
from Module B, *not* by reading `slowsvc.c`. (In a real incident you'd start with the
trace, not the source.)

The trick with tail latency: a flat function trace or a profiler *average* won't show
it — you have to look at requests **one at a time** and catch the slow one in the act.

## Graduated hints

<details><summary>Hint 1 — how do I see per-request latency, not an average?</summary>

`function_graph` times each call. Scope it to the handler and watch every request:

```sh
T=/sys/kernel/tracing
echo slowsvc_read > $T/set_graph_function
echo function_graph > $T/current_tracer
echo 1 > $T/tracing_on
for i in $(seq 1 10); do cat /proc/slowsvc >/dev/null; done
cat $T/trace
```
</details>

<details><summary>Hint 2 — what am I looking for in the graph?</summary>

Most `slowsvc_read()` calls return in single-digit microseconds. Some take
**thousands** — and unlike the fast ones, the slow ones aren't leaves: they *call into
something*. Read what's nested under the slow call.
</details>

<details><summary>Hint 3 — the cause</summary>

The slow requests detour through a **sleep**: `slowsvc_read() → msleep() →
schedule_timeout() → schedule()`. The handler blocks on those requests; the CPU is
idle (that's why utilization looked fine) but the *request* waits ~20 ms.
</details>

## 🧾 Post-mortem

<details><summary>open after you've driven it — ground truth + the lesson</summary>

`slowsvc_read()` counts requests and, on **every 5th** one, calls `msleep(20)`:

```c
if (++reqs % 5 == 0)
        msleep(20);
```

So 20% of requests sleep 20 ms while the other 80% are instant — a bimodal latency
distribution that *any average hides*. `function_graph` exposes it because it times
each request individually and shows the `msleep` detour the slow ones take.

The lesson: **tail latency lives in the requests you didn't average.** When p50 is
great but p99 is awful and the box looks idle, something is *blocking* on a fraction of
requests. Trace per-request (function_graph) or measure the distribution (a hist
trigger on a latency, B4) — never trust the mean. The same shape shows up for real as a
lock occasionally contended, a cache miss that hits disk, or a periodic kthread
stealing the CPU.
</details>

## How this scenario is graded

The check confirms the symptom is reproducible and the diagnostic path works:
`function_graph` localizes the slow requests to a sleep inside `slowsvc_read()`. In a
real on-call setting, a human (or an LLM on-call lead) grades *your* evidence — the
trace you captured and the one-line root cause you wrote.

## Further reading

- [docs.kernel.org — ftrace](https://docs.kernel.org/trace/ftrace.html) — `function_graph` (per-call durations), `set_graph_function`, and the latency tracers for chasing tail latency.
- [Brendan Gregg — Latency Heat Maps](https://www.brendangregg.com/HeatMaps/latency.html) — why averages hide tail latency, and how to see the whole distribution.
