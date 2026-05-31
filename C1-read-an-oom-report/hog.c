// SPDX-License-Identifier: GPL-2.0
/* hog.c — grows its resident set until the cgroup OOM killer reaps it, so this
 * lesson has a real OOM report to read. (Same idea as the Wheel's hog.) */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(void)
{
	const size_t chunk = 1u << 20;   /* 1 MiB */
	size_t total = 0;

	fprintf(stderr, "svc: growing the working set...\n");
	for (;;) {
		char *p = malloc(chunk);

		if (!p)
			return 1;
		memset(p, 0xAB, chunk);   /* touch the pages so they become resident */
		total += chunk;
	}
}
