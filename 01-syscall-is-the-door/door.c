/*
 * door.c — the smallest possible walk through the syscall door.
 *
 * It asks the kernel one question (getpid) and prints the answer. Compiled
 * statically by check.sh and run inside the guest under strace, so you can see
 * the boundary crossing from userspace while your printk sees it from inside the
 * kernel. Same event, two sides of the door.
 */
#include <stdio.h>
#include <unistd.h>
#include <sys/types.h>

int main(void)
{
	pid_t p = getpid();           /* <-- the door: traps into SYSCALL_DEFINE0(getpid) */
	printf("door: my pid is %d\n", (int)p);
	return 0;
}
