# Out-of-tree kernel module build (kbuild). ../check.sh overrides KDIR to point at
# the pinned kernel tree on the build volume. See 02-printk-and-ring-buffer for notes.

obj-m := h2_wedge.o

KDIR ?= /work/harness/.build/linux-6.18.33
PWD  := $(shell pwd)

.PHONY: all clean
all:
	$(MAKE) -C $(KDIR) M=$(PWD) modules

clean:
	$(MAKE) -C $(KDIR) M=$(PWD) clean
