# Out-of-tree build for the C2 demo module. ../check.sh overrides KDIR to the
# KASAN OVERLAY kernel tree (harness/.build/kasan-obj) — the module MUST be built
# against the same KASAN kernel the guest boots, so the compiler instruments it
# and KASAN can see its accesses. See harness/build-kasan-kernel.sh.

obj-m := kasan_oob.o kasan_uaf.o kasan_df.o

KDIR ?= /work/harness/.build/linux-6.18.33-kasan
PWD  := $(shell pwd)

.PHONY: all clean
all:
	$(MAKE) -C $(KDIR) M=$(PWD) modules

clean:
	$(MAKE) -C $(KDIR) M=$(PWD) clean
