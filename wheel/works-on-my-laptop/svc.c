/*
 * svc.c — a stand-in for "novel software" that warms a pool of file descriptors
 * on startup (think: a connection/handle pool). On a dev laptop with a generous
 * RLIMIT_NOFILE it sails through; on a prod-shaped box with a low limit it
 * face-plants partway through warmup with a cryptic message and exit code 3.
 *
 * The bug is NOT here — the source is correct. The fault is in the environment
 * the kernel hands the process. That's the whole point of the scenario.
 */
#include <stdio.h>
#include <fcntl.h>
#include <errno.h>
#include <string.h>
#include <unistd.h>

#define POOL 256

int main(void)
{
	int fds[POOL];
	int i;

	for (i = 0; i < POOL; i++) {
		fds[i] = open("/proc/self/status", O_RDONLY);
		if (fds[i] < 0) {
			/* The cryptic startup failure the on-call sees. Note we DO
			 * surface the errno string — many real services don't, which
			 * is exactly why the page is a mystery. */
			fprintf(stderr, "svc: pool warmup failed at slot %d: %s\n",
				i, strerror(errno));
			return 3;
		}
	}

	fprintf(stderr, "svc: pool of %d descriptors ready\n", POOL);
	for (i = 0; i < POOL; i++)
		close(fds[i]);
	return 0;
}
