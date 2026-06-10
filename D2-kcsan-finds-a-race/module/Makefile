# Out-of-tree kernel module build (kbuild). ../check.sh overrides KDIR to point at
# the DEBUG (lockdep+KCSAN) kernel tree on the build volume — Module D's modules
# must build against the tree they boot on, so KCSAN instruments their accesses.

obj-m := d2_race.o

KDIR ?= /work/harness/.build/linux-6.18.33-debug
PWD  := $(shell pwd)

.PHONY: all clean
all:
	$(MAKE) -C $(KDIR) M=$(PWD) modules

clean:
	$(MAKE) -C $(KDIR) M=$(PWD) clean
