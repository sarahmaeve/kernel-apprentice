// SPDX-License-Identifier: GPL-2.0
/*
 * trigger.c — call getpid via the RAW syscall so it always enters the kernel.
 *
 * glibc's getpid() wrapper can be cached or served without a real trap; syscall()
 * goes straight through the door, so the kprobe/ftrace probe we attached to the
 * live kernel is guaranteed to fire. Used by ../check.sh.
 */
#include <stdio.h>
#include <unistd.h>
#include <sys/syscall.h>

int main(void)
{
	long pid = syscall(SYS_getpid);
	printf("trigger: syscall(SYS_getpid) = %ld\n", pid);
	return 0;
}
