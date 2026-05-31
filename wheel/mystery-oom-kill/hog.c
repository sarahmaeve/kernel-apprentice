// SPDX-License-Identifier: GPL-2.0
/*
 * hog.c — a stand-in "service" that grows its resident set on startup (think: a
 * cache warming up, or a request that buffers too much). Run inside a cgroup with a
 * small memory.max, it climbs past the limit and the kernel's cgroup OOM killer
 * reaps it. Nothing is wrong with the code — the box's memory limit is too small for
 * the workload. That's the whole scenario.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

int main(void)
{
	const size_t chunk = 1u << 20;   /* 1 MiB */
	size_t total = 0;

	fprintf(stderr, "svc: warming up, growing the working set...\n");
	for (;;) {
		char *p = malloc(chunk);

		if (!p) {
			fprintf(stderr, "svc: malloc failed at %zu MiB\n", total >> 20);
			return 1;
		}
		memset(p, 0xAB, chunk);   /* touch the pages so they become resident */
		total += chunk;
		if ((total >> 20) % 8 == 0)
			fprintf(stderr, "svc: %zu MiB resident\n", total >> 20);
	}
}
