# Out-of-tree kernel module build (kbuild).
#
# `obj-m` tells kbuild to build hello.ko. The real build is delegated to the
# pinned kernel tree's build system via `make -C $(KDIR) M=$(PWD)`. ../check.sh
# overrides KDIR to point at harness/.build/linux-<version>; the default below is
# only a convenience for hand-building from inside the workbench.

obj-m := hello.o

KDIR ?= /work/harness/.build/linux-6.18.33
PWD  := $(shell pwd)

.PHONY: all clean
all:
	$(MAKE) -C $(KDIR) M=$(PWD) modules

clean:
	$(MAKE) -C $(KDIR) M=$(PWD) clean
