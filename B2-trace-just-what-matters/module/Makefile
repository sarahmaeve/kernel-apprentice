# Out-of-tree build for the B2 worker module. ../check.sh overrides KDIR to point
# at the pinned base kernel tree on the build volume. See 06 for notes.

obj-m := b2_worker.o

KDIR ?= /work/harness/.build/linux-6.18.33
PWD  := $(shell pwd)

.PHONY: all clean
all:
	$(MAKE) -C $(KDIR) M=$(PWD) modules

clean:
	$(MAKE) -C $(KDIR) M=$(PWD) clean
