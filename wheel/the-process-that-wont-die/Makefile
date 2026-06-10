# Out-of-tree kernel module build (kbuild) for the wheel's injected fault.
# check.sh overrides KDIR to point at the pinned kernel tree on the build volume.

obj-m := vjournal.o

KDIR ?= /work/harness/.build/linux-6.18.33
PWD  := $(shell pwd)

.PHONY: all clean
all:
	$(MAKE) -C $(KDIR) M=$(PWD) modules

clean:
	$(MAKE) -C $(KDIR) M=$(PWD) clean
