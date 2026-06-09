# Out-of-tree kernel module build (kbuild). ../check.sh overrides KDIR to point at
# the pinned kernel tree on the build volume. See 02-printk-and-ring-buffer for notes.
#
# -g embeds DWARF in the .ko so scripts/faddr2line can map an oops RIP
# (e0_write+0x.../0x...) back to a file:line — the Touch step of this lesson.
# (The base kernel skips debug info; the module carries its own.)
ccflags-y := -g

obj-m := e0_anatomy.o

KDIR ?= /work/harness/.build/linux-6.18.33
PWD  := $(shell pwd)

.PHONY: all clean
all:
	$(MAKE) -C $(KDIR) M=$(PWD) modules

clean:
	$(MAKE) -C $(KDIR) M=$(PWD) clean
