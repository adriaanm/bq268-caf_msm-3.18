# BQ268 Kernel — CAF 3.18 Branch

## Reproducibility

Every repeated command must be tracked in git as a self-describing recipe. The `justfile` is the single entry point for all build, flash, and analysis steps. If you find yourself running a command more than once, add it as a `just` recipe.

Run `just` to list all available recipes.

## Workflow: Commit Before Flash

Every kernel change that will be flashed MUST follow this discipline:

1. **Commit first** — create a git commit with the changes before building/flashing
2. **Build and flash** — `just bootimg`, then `just fastboot-boot`
3. **Record outcome** — amend the commit message with the boot test result:
   - `BOOT TEST: PASS` — device boots successfully
   - `BOOT TEST: FAIL (description)` — device did not boot, with brief failure description
   - `BOOT TEST: PARTIAL (description)` — boots but with issues
4. **Record experiment** — `just note "PASS: description"` (records on HEAD)

## Tasks & Experiments — ALWAYS use `just` recipes

**IMPORTANT: Never use raw `git notes` commands.** Always use the `just` recipes:

- **`just tasks`** — show current tasks
- **`just task-add "description"`** — add a new task
- **`just task-start "pattern"`** — mark a task in-progress
- **`just task-done "pattern"`** — mark a task done
- **`just experiments`** — show experiment log
- **`just note "message"`** — record an experiment outcome on HEAD

## Current State (2026-03-18)

Kernel version: **3.18.140-bq268** (flashed to boot partition)
Rootfs: Alpine 3.21.3 on userdata (p36), OpenRC

### Working Hardware
- **Display**: ST7735S 128x160 SPI via fbtft (ported from mainline 6.19 staging)
- **USB serial**: android_usb ACM (acm_transports="tty" default in android.c)
- **USB ECM**: Alpine usb-gadget-ecm service
- **WiFi**: WCNSS/Pronto + prima wlan.ko, wpa_supplicant connects to AP
- **Audio**: msm8909-snd-card with WCD/Cajon codec (14+ PCM devices)
- **Modem**: PIL loads firmware, SMD channels open (needs SIM for data path)
- **SSH**: dropbear over WiFi

### Boot Configuration
- No initramfs — kernel mounts p36 directly
- Cmdline: `root=/dev/mmcblk0p36 rootfstype=ext4 rootwait rw console=tty0 console=ttyHSL0,115200 fbcon=rotate:3 consoleblank=0`
- `.scmversion` file suppresses git hash in kernel version

## Toolchain

**GCC 4.9.4 only.** Clang 14 cross-compilation was attempted but the resulting kernel does not boot.

**Always use `bootimg-gcc` for flashable images.**

## Key Patches (relative to stock CAF 3.18)

### android_usb ACM default (drivers/usb/gadget/android.c)
- `acm_transports[32] = "tty"` — hardcode default so gserial_alloc_line() creates /dev/ttyGS0

### SPI driver binding (arch/arm/boot/dts/qcom/msm8909-bq268.dts)
- Compatible changed to `qcom,spi-qup-v2.2.1` (stock `v2` doesn't match spi-qup.c)
- Clock-names: `"core","iface"` (not `"iface_clk","core_clk"`)
- Single reg entry, no BAM properties

### fbtft display (drivers/staging/fbtft/)
- Ported from mainline 6.19, adapted for 3.18 APIs
- ST7735S init sequence from bootloader (panel_st7735s_cmd.h)
- txbuflen=4096 to avoid SPI FIFO overrun
- Reset GPIO: GPIO_ACTIVE_LOW for correct polarity
- MDSS SPI display disabled in DTS (fbtft replaces it)

### Audio codec probe (sound/soc/codecs/msm8x16-wcd.c)
- Removed `apr_get_subsys_state()` check from SPMI probe — codec hardware can probe independently, APR/DSP only needed for playback

### APR state mapping (drivers/soc/qcom/qdsp6v2/apr_v3.c)
- Map APR_SUBSYS_UP → APR_SUBSYS_LOADED (MSM8909 has no separate LPASS)

### APR modem notifier (drivers/soc/qcom/qdsp6v2/apr.c)
- Removed boot_count=2 skip that dropped first modem notifications

### WiFi
- prima/wlan.ko built as external module
- Needs WCNSS_qcom_cfg.ini from prima/firmware_bin/ on rootfs
- Firmware: modem partition has wcnss.mdt + segments, persist has NV data

## Known Issues

- MBHC disable via kernel code (`of_property_read_bool` in msm8952.c) crashes on boot — likely GCC 4.8 miscompilation. Disabled in DTS instead.
- Modem SSR ~60s after boot without SIM card (expected)
- BAM-DMUX/rmnet data path requires SIM for SMSM A2_POWER_CONTROL handshake
- SPI FIFO overrun at 16MHz (OUTPUT_OVER_RUN) — mitigated by txbuflen=4096
- gcc-wrapper.py: dot11f.c:4627 warning allowlisted for prima build

## Iteration Infrastructure

- `reboot-bootloader` binary: tools/reboot-bootloader.c (IMEM magic 0x77665500 + warm reset)
- Serial I/O via /dev/ttyACM0 (stty raw + timeout cat)
- SSH over WiFi: `sshpass -p bq268 ssh root@<device-ip>`
- Just recipes: cycle, recycle, serial, dev-reboot, boot, wait-serial

## Rootfs Requirements (for ~/bq268-pmos agent)

- wlan.ko at `/lib/modules/3.18.140-bq268/wlan.ko`
- WCNSS_qcom_cfg.ini at `/lib/firmware/wlan/prima/WCNSS_qcom_cfg.ini` (from prima/firmware_bin/)
- reboot-bootloader at `/sbin/reboot-bootloader` (from tools/reboot-bootloader)
- USB gadget: detect android_usb via `/sys/class/android_usb/android0`
- WiFi: `cat /dev/wcnss_wlan &` before `insmod wlan.ko`
