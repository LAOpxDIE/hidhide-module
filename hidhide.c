// SPDX-License-Identifier: GPL-2.0
/*
 * hidhide.c - Rewrite an external HID input device identity so it presents
 * as an internal input device. The current matcher targets USB multi-touch.
 *
 * How it works:
 *   Touch drivers fill input_dev->id / ->name / ->phys BEFORE calling
 *   input_register_device(). A kprobe pre-handler on that function sees
 *   the fully populated struct, so we rewrite the identity fields for
 *   the matching VID/PID right there. Every layer above the input core
 *   (evdev, getevent, Android InputReader, InputDevice.isExternal(),
 *   /proc/bus/input/devices, uevent, ...) then sees a builtin I2C panel.
 *
 * Build:  see Makefile (needs kernel source/headers matching the device)
 * Load:   insmod hidhide.ko [target_vid=0xXXXX] [target_pid=0xXXXX] \
 *                          [fake_name=xxx] [fake_phys=xxx]
 */

#include <linux/kernel.h>
#include <linux/module.h>
#include <linux/kprobes.h>
#include <linux/input.h>
#include <linux/slab.h>
#include <asm/ptrace.h>

/* ===== defaults, all overridable as insmod params =====
 * target_vid = 0 (default): AUTO mode - disguise ANY external USB device
 * that is a multi-touch digitizer (BTN_TOUCH + ABS_MT_SLOT), regardless of
 * its original USB identity.
 * target_vid != 0: explicit mode, only that VID/PID is touched. */
static ushort target_vid = 0;
static ushort target_pid = 0;
static char  *fake_name = "goodix_ts";      /* builtin panel driver name of target model */
static char  *fake_phys = "i2c/1-005d";     /* plausible I2C topology string */
/* ================================================================= */

module_param(target_vid, ushort, 0444);
module_param(target_pid, ushort, 0444);
module_param(fake_name,  charp,  0444);
module_param(fake_phys,  charp,  0444);
MODULE_PARM_DESC(target_vid, "USB VID of the external HID device to rewrite");
MODULE_PARM_DESC(target_pid, "USB PID of the external HID device to rewrite");
MODULE_PARM_DESC(fake_name,  "Name to present (builtin panel driver name)");
MODULE_PARM_DESC(fake_phys,  "Physical path to present (fake I2C topology)");

static int __kprobes hidhide_pre(struct kprobe *p, struct pt_regs *regs)
{
	/* input_register_device(struct input_dev *dev): arm64 arg0 = x0 */
	struct input_dev *dev = (struct input_dev *)PT_REGS_PARM1(regs);

	if (!dev)
		return 0;

	if (dev->id.bustype != BUS_USB)
		return 0;

	/* explicit mode: only the configured VID/PID */
	if (target_vid &&
	    (dev->id.vendor != target_vid || dev->id.product != target_pid))
		return 0;

	/* must be a multi-touch digitizer (BTN_TOUCH + ABS_MT_SLOT) */
	if (!test_bit(BTN_TOUCH, dev->keybit) ||
	    !test_bit(ABS_MT_SLOT, dev->absbit))
		return 0;

	{
		ushort ov = dev->id.vendor, op = dev->id.product;
		char *name_copy, *phys_copy;

		/*
		 * input_dev retains these pointers after registration. Module static
		 * storage disappears on rmmod, so use small persistent heap copies to
		 * avoid dangling pointers. They intentionally live until reboot.
		 */
		name_copy = kstrdup(fake_name, GFP_ATOMIC);
		phys_copy = kstrdup(fake_phys, GFP_ATOMIC);
		if (!name_copy || !phys_copy) {
			kfree(name_copy);
			kfree(phys_copy);
			return 0;
		}

		dev->id.bustype = BUS_I2C;   /* 0x18, pretend internal bus */
		dev->id.vendor  = 0;
		dev->id.product = 0;
		dev->id.version = 0;         /* USB bcdDevice leaks origin */

		/*
		 * struct input_dev { const char *name; const char *phys;
		 * const char *uniq; ... }  -- these are POINTERS, not arrays.
		 *
		 * The original draft did snprintf(dev->name, ...) which writes
		 * into the old target buffer. That buffer normally lives in
		 * the HID driver's read-only data section -> kernel oops.
		 * Re-pointing the pointers is the correct (and atomic-enough)
		 * way to swap the identity.
		 */
		dev->name = name_copy;
		dev->phys = phys_copy;  /* original is "usb-..." -> leaks the bus */
		dev->uniq = NULL;       /* often a MAC/serial -> leak, drop it */

		pr_info("[hidhide] %04x:%04x disguised as \"%s\" (%s, I2C)\n",
			ov, op, fake_name, fake_phys);
	}
	return 0;
}

static struct kprobe hidhide_kp = {
	.symbol_name = "input_register_device",
	.pre_handler = hidhide_pre,
};

static int __init hidhide_init(void)
{
	int ret = register_kprobe(&hidhide_kp);

	if (ret < 0) {
		pr_err("[hidhide] kprobe register failed: %d\n", ret);
		return ret;
	}
	pr_info("[hidhide] loaded, kprobe at %p, watching %04x:%04x\n",
		hidhide_kp.addr, target_vid, target_pid);
	return 0;
}

static void __exit hidhide_exit(void)
{
	unregister_kprobe(&hidhide_kp);
	pr_info("[hidhide] unloaded\n");
}

module_init(hidhide_init);
module_exit(hidhide_exit);
MODULE_LICENSE("GPL");
MODULE_AUTHOR("HIDHide contributors");
MODULE_DESCRIPTION("Rewrite external HID input device identity as an internal device");
MODULE_VERSION("1.3.0");
