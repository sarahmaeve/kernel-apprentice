// SPDX-License-Identifier: GPL-2.0
/* trigger.c — call getpid a fixed number of times so the module's counter has
 * something to count. Built static and run by the guest's /init in ../check.sh. */
#include <stdio.h>
#include <unistd.h>
#include <sys/syscall.h>

#define N 50

int main(void)
{
	for (int i = 0; i < N; i++)
		syscall(SYS_getpid);
	printf("trigger: called getpid %d times\n", N);
	return 0;
}
