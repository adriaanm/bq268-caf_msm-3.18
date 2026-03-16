# Plan: Boot CAF 3.18 with Minimal Linux Userspace

## Goal

Get a working Linux console (USB serial gadget) on the CAF 3.18.140
kernel to use it as a stable reference platform for investigating
DDR/PMIC instability on mainline 6.19.

**Why this matters:** The mainline 6.19 kernel suffers silent PMIC
hard-resets during sustained page allocation (~480 pages with rootfs,
~1888 with minimal initramfs). The CAF 3.18 kernel is rock solid.
By booting CAF with enough userspace to dump registers, we can compare
BIMC, GCC, RPM, and PMIC state between the two kernels and identify
what CAF does differently (DDR timing? bandwidth votes? voltage?
clock config? something else entirely?).

## Background: Why NOT port CAF to mainline 3.18

Mainline 3.18.140 has zero MSM8909 support. Porting would require
transplanting ~20K+ lines of tightly coupled Qualcomm infrastructure:

| Subsystem              | CAF lines | In mainline 3.18? |
|------------------------|-----------|-------------------|
| msm_bus (BIMC/NoC)     | 15,787    | No                |
| RPM/SMD IPC            | ~3,000    | No                |
| clock-gcc-8909         | ~800      | No                |
| clock-rpm-8909         | ~100      | No                |
| msm_otg USB            | 4,700     | No                |
| SPMI/PMIC              | ~2,000    | Partial           |
| pinctrl-msm8909        | ~500      | No                |

Critically, the CAF infrastructure IS the stability — its msm_bus,
RPM voting, clock management, and PMIC sequencing work as Qualcomm
designed. Porting pieces risks introducing the instability we're
trying to diagnose.

## Phase 1: Get USB serial console on CAF 3.18

### Defconfig changes

Starting from `arch/arm/configs/msm8909_defconfig`, enable:

```
CONFIG_USB_G_SERIAL=y           # USB serial gadget (/dev/ttyGS0)
CONFIG_USB_GADGET_VBUS_DRAW=500
```

Consider disabling (reduce boot noise, avoid Android dependencies):

```
# CONFIG_ANDROID is not set
# CONFIG_ANDROID_BINDER_IPC is not set
# CONFIG_SECURITY_SELINUX is not set
```

### USB gadget architecture (CAF 3.18)

CAF uses `android_usb` gadget driver, NOT modern configfs. Key files:
- `drivers/usb/phy/phy-msm-usb.c` — msm_otg PHY driver (4700+ lines)
- `drivers/usb/gadget/ci13xxx_msm.c` — Chipidea USB controller
- USB controller address: `0x78d9000` (HSUSB)
- PHY: SNPS Femto PHY (type 3) with ULPI interface

The msm_otg driver requires: multiple clocks (core, iface, xo, sleep,
phy_reset, phy_por, phy_csr, plus bus/NoC clocks), regulators
(HSUSB_3p3, HSUSB_1p8, hsusb_vdd_dig from PM8909), and bus scaling
via msm_bus_scale_register_client().

Two approaches for USB serial:
1. **CONFIG_USB_G_SERIAL=y** — standalone serial gadget, simplest
2. **android_usb with serial function** — may need userspace config

Try option 1 first. If it conflicts with android_usb, disable
android_usb and enable the standalone gadget.

### Initramfs

Build a minimal initramfs with:
- busybox (statically linked, ARM hard-float)
- `/init` script that:
  1. Mounts proc, sys, devtmpfs
  2. Configures USB serial gadget (if not auto)
  3. Spawns getty on `/dev/ttyGS0`
  4. Also spawns getty on `/dev/ttyHSL0` (UART, in case USB fails)

```sh
#!/bin/sh
mount -t proc proc /proc
mount -t sysfs sys /sys
mount -t devtmpfs dev /dev

# USB serial gadget should auto-enumerate if CONFIG_USB_G_SERIAL=y
# If using configfs instead:
# mount -t configfs none /sys/kernel/config
# (configure gadget here)

echo "CAF 3.18 booted — starting consoles"
setsid sh -c 'exec sh </dev/ttyGS0 >/dev/ttyGS0 2>&1' &
exec sh
```

### Build

Use GCC 4.9.4 (see CLAUDE.md — Clang doesn't boot on this kernel).

```sh
just bootimg-gcc    # or equivalent recipe
```

Append the initramfs to the kernel image or pass via bootimg ramdisk.

### Boot

```sh
just fastboot-boot  # or equivalent recipe
```

On the host, connect via USB serial:
```sh
picocom /dev/ttyACM0 -b 115200
```

### Potential blockers

1. **USB_G_SERIAL vs android_usb conflict** — if both are enabled,
   android_usb may grab the UDC first. Solution: disable android_usb
   in defconfig or DTS.

2. **DTB format** — CAF uses CONFIG_BUILD_ARM_APPENDED_DTB_IMAGE=y.
   Our bootloader (aboot) expects appended DTB. The build recipes
   should already handle this.

3. **Kernel cmdline** — aboot passes its own cmdline. We need
   `console=ttyGS0` and/or `console=ttyHSL0,115200`. If aboot
   overrides, we may need to patch cmdline in DTS or aboot.

4. **Missing /dev nodes** — CAF expects Android ueventd. Our initramfs
   uses devtmpfs (`mount -t devtmpfs dev /dev`), which should work
   if `CONFIG_DEVTMPFS=y` and `CONFIG_DEVTMPFS_MOUNT=y`.

5. **Init expectations** — CAF defconfig may have `CONFIG_INIT=/init`
   pointing at Android init. Ensure cmdline has `init=/init` pointing
   at our busybox init script, or `rdinit=/init` for initramfs.

## Phase 2: Register dump comparison

Once we have a shell on CAF 3.18, dump hardware state:

### BIMC registers (DDR controller)
```sh
# BIMC base: 0x00400000
devmem2 0x00400000 w   # BIMC_BRIC_BASE
devmem2 0x00448000 w   # BIMC_M_APP_MPORT (CPU master)
devmem2 0x00450000 w   # BIMC_M_GPU_MPORT (GPU master)
devmem2 0x00468000 w   # BIMC_S_DDR0 (DDR slave)
# Dump QoS registers, BKE state, priorities
```

### GCC clock registers
```sh
# GCC base: 0x01800000
# Key: BIMC clocks, DDR-related PLLs
devmem2 0x01831000 w   # GCC_BIMC_* registers
devmem2 0x01821000 w   # GPLL0
```

### RPM state
```sh
# Check /sys/kernel/debug/rpm* or /sys/kernel/debug/clk/
cat /sys/kernel/debug/clk/clk_summary 2>/dev/null
cat /sys/kernel/debug/rpm_stats 2>/dev/null
cat /sys/kernel/debug/rpm_master_stats 2>/dev/null
```

### PMIC registers
```sh
# PM8909 via SPMI — if debugfs available
cat /sys/kernel/debug/spmi/spmi-0/data 2>/dev/null
# Or dump specific regulator voltages
cat /sys/kernel/debug/regulator/regulator_summary 2>/dev/null
```

### Comparison script

Create a script that dumps all registers to a file, then diff against
the same dump taken from mainline 6.19. Key areas to compare:
- BIMC QoS configuration (BKE bypass vs enabled, priorities)
- DDR PLL state (SRC_SEL, frequency, lock status)
- VDDMX/VDDCX voltage levels
- Bus bandwidth vote state in RPM
- Clock enable/disable state for BIMC, PCNOC, SNOC

## Phase 3: Apply findings to mainline 6.19

Whatever CAF does differently, replicate in 6.19 via:
- DTS property changes (voltages, OPPs, clock rates)
- Early init code (before RPM settles)
- ICC driver adjustments
- PMIC regulator constraints

The mainline 6.19 kernel and BQ268 device tree live at:
- `~/bq268-linux/arch/arm/boot/dts/qcom/qcom-msm8909-udotech-bq268.dts`
- `~/bq268-linux/arch/arm/boot/dts/qcom/qcom-msm8909.dtsi`
- `~/bq268-linux/drivers/interconnect/qcom/msm8909.c`

The mainline memory stability investigation is documented at:
- `~/bq268-linux/docs/memory-stability.md`

## Key file locations (CAF 3.18)

| Purpose | Path |
|---------|------|
| Board DTS | `arch/arm/boot/dts/qcom/msm8909*.dts*` |
| SoC DTSI | `arch/arm/boot/dts/qcom/msm8909.dtsi` |
| Defconfig | `arch/arm/configs/msm8909_defconfig` |
| USB OTG/PHY | `drivers/usb/phy/phy-msm-usb.c` |
| USB gadget CI | `drivers/usb/gadget/ci13xxx_msm.c` |
| UART driver | `drivers/tty/serial/msm_serial_hs_lite.c` |
| Clock GCC | `drivers/clk/msm/clock-gcc-8909.c` |
| Clock RPM | `drivers/clk/msm/clock-rpm-8909.c` |
| Bus scaling | `drivers/platform/msm/msm_bus/` (22 files) |
| RPM SMD | `drivers/soc/qcom/rpm-smd.c` |
| PMIC/SPMI | `drivers/mfd/qcom-spmi-pmic.c` |
| SPI (display) | `drivers/spi/spi-qup.c` |

## Success criteria

1. CAF 3.18 boots with USB serial console — interactive shell
2. Register dumps captured for BIMC, GCC, RPM, PMIC
3. Same dumps captured from mainline 6.19 for comparison
4. Differences identified and documented
5. Fix applied to mainline 6.19, memory stability test passes
