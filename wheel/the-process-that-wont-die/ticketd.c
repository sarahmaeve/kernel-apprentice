/* ticketd — the "service": journals one ticket per loop through the vendor
 * driver (/proc/vjournal), logging each step to stdout. The app code is fine. */
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>

int main(void)
{
	int fd = open("/proc/vjournal", O_WRONLY);

	if (fd < 0) {
		perror("ticketd: open /proc/vjournal");
		return 1;
	}
	for (int i = 1;; i++) {
		char rec[64];
		int n = snprintf(rec, sizeof(rec), "ticket %d\n", i);

		printf("ticketd: journaling ticket %d\n", i);
		fflush(stdout);
		if (write(fd, rec, n) < 0) {
			perror("ticketd: write");
			return 1;
		}
		printf("ticketd: ticket %d committed\n", i);
		fflush(stdout);
		usleep(200000);
	}
}
