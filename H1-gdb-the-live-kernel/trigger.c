// SPDX-License-Identifier: GPL-2.0
/*
 * trigger.c — call getpid via the raw syscall, so a gdb breakpoint set on the
 * kernel handler (__do_sys_getpid) is guaranteed to fire. Run in a loop by the
 * guest's /init in ../check.sh.
 */
#include <unistd.h>
#include <sys/syscall.h>

int main(void)
{
	for (int i = 0; i < 100; i++)
		syscall(SYS_getpid);
	return 0;
}
