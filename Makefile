# hidhide.ko build
#
# The module MUST be built against the exact kernel the device runs
# (`uname -r` on the phone). Otherwise insmod fails with
# "Invalid module format" (vermagic mismatch).
#
# Android cross-build example (GKI / vendor kernel source tree):
#   make KDIR=/path/to/device-kernel-source \
#        ARCH=arm64 \
#        CROSS_COMPILE=aarch64-linux-gnu-
#
# Native build on a Linux box with headers installed:
#   make

obj-m := hidhide.o

KDIR          ?= /lib/modules/$(shell uname -r)/build
ARCH          ?= arm64
CROSS_COMPILE ?=

all:
	$(MAKE) -C $(KDIR) M=$(PWD) ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) modules

clean:
	$(MAKE) -C $(KDIR) M=$(PWD) ARCH=$(ARCH) CROSS_COMPILE=$(CROSS_COMPILE) clean

.PHONY: all clean
