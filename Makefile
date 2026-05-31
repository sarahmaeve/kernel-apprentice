# Host-side orchestration for the kernel-apprentice workbench.
#
# Runs on the host and only drives the container runtime; the real work (kernel
# build, initramfs, QEMU boot, checks) happens INSIDE the container via
# harness/*.sh. See DESIGN.md §4-5.
#
# Portable across contributor machines (a project goal):
#   * Runtime is configurable:        make RUNTIME=podman ...
#   * colima is used only where present (macOS); Linux hosts skip it.
#   * Workbench + guest are pinned to linux/amd64 on EVERY host, so lesson
#     file:line references match for everyone. Native on Intel/x86 Linux;
#     emulated-but-identical on Apple Silicon.
#   * /dev/kvm is passed through only when the host actually has it.
#
# First run:  make image && make kernel && make check LESSON=01-syscall-is-the-door
# Day-to-day: make check LESSON=02-printk-and-ring-buffer

IMAGE       := kernel-apprentice
CURDIR      := $(shell pwd)
RUNTIME     ?= docker
PLATFORM    ?= linux/amd64

# Max specs for THIS machine come from userspecs.txt (2019 Intel Mac). Other
# contributors can override on the command line: make up COLIMA_ARGS="--cpu 4 ..."
COLIMA_ARGS ?= --cpu 6 --memory 8 --disk 60

# Pass /dev/kvm through only if the host exposes it (x86_64 Linux). Empty on macOS.
KVM := $(shell [ -e /dev/kvm ] && echo --device /dev/kvm)

# Repo bind-mounted at /work for the lesson files + scripts. The kernel build,
# however, MUST live on a Linux-native filesystem: the macOS virtiofs bind mount
# can't create the kernel tree's relative symlinks (tar fails with EACCES, and the
# half-made links even resist rm). So harness/.build is a named VOLUME; only the
# .cache download stays on the host bind mount. The volume persists across
# container + colima restarts (build once) until `make clean`.
VOLUME := kernel-apprentice-build
MOUNTS := -v "$(CURDIR)":/work -v $(VOLUME):/work/harness/.build

RUN_IT := $(RUNTIME) run --rm -it --platform=$(PLATFORM) $(KVM) $(MOUNTS) $(IMAGE)
RUN    := $(RUNTIME) run --rm    --platform=$(PLATFORM) $(KVM) $(MOUNTS) $(IMAGE)

LESSON ?=
.DEFAULT_GOAL := help
.PHONY: help up down doctor image shell kernel initramfs check status validate reset clean distclean

help: ## Show available targets
	@awk 'BEGIN{FS=":.*##"} /^[a-zA-Z_-]+:.*##/ {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

up: ## Start the container VM if needed (macOS/colima); no-op where colima is absent
	@if command -v colima >/dev/null 2>&1; then \
	   colima status >/dev/null 2>&1 || colima start $(COLIMA_ARGS); \
	 else echo "no colima here — assuming a native $(RUNTIME) daemon is running"; fi

down: ## Stop the colima VM (macOS)
	@command -v colima >/dev/null 2>&1 && colima stop || echo "no colima to stop"

doctor: ## Verify host prerequisites (runtime reachable)
	@command -v $(RUNTIME) >/dev/null || { echo "FAIL: $(RUNTIME) not installed"; exit 1; }
	@$(RUNTIME) info >/dev/null 2>&1 || { echo "FAIL: $(RUNTIME) daemon not reachable (try 'make up')"; exit 1; }
	@echo "OK: runtime=$(RUNTIME) platform=$(PLATFORM) kvm=$(if $(KVM),yes,no)"

image: up ## Build (or rebuild) the workbench image
	$(RUNTIME) build --platform=$(PLATFORM) -t $(IMAGE) .

shell: image ## Open an interactive workbench shell
	$(RUN_IT) bash

kernel: image ## Build the pinned kernel — slow ONE-TIME; cached in harness/.build
	$(RUN) harness/build-kernel.sh; rc=$$?; $(RUN) harness/gen-status.sh; exit $$rc

initramfs: image ## Build the base BusyBox initramfs
	$(RUN) harness/build-initramfs.sh

check: image ## Run lesson check(s): make check LESSON=01-syscall-is-the-door (omit = all)
	$(RUN) harness/check.sh $(LESSON); rc=$$?; $(RUN) harness/gen-status.sh; exit $$rc

status: image ## Regenerate the dashboard's live status (assets/status.js, gitignored)
	$(RUN) harness/gen-status.sh

validate: ## Validate the HTML docs (tag balance, links, css vars, fonts); host-only, no container
	python3 harness/validate-html.py

reset: ## Reset CHALLENGE lessons to their committed skeleton (lightweight). LESSON=<id> for one.
	./harness/reset.sh $(LESSON)

clean: ## Remove the kernel build (named volume) + host artifacts; keeps the download cache
	-$(RUNTIME) volume rm $(VOLUME) 2>/dev/null
	rm -rf harness/.build assets/status.js

distclean: clean ## Also remove the downloaded source tarball cache
	rm -rf harness/.cache
