# BQ268 CAF 3.18 — minimal Linux userspace
# USB serial console + register dump for DDR/PMIC comparison with mainline 6.19

toolchain := "/opt/toolchains/gcc-linaro-4.9.4-2017.01-x86_64_arm-linux-gnueabihf/bin/arm-linux-gnueabihf-"
out := "output"
mkbootimg := "tools/mkbootimg/mkbootimg.py"
defconfig := "bq268_defconfig"
cmdline := "androidboot.hardware=qcom msm_rtb.filter=0x237 ehci-hcd.park=3 androidboot.bootdevice=7824900.sdhci lpm_levels.sleep_disabled=1 earlyprintk panic=5 ramoops.mem_address=0x9ff00000 ramoops.mem_size=0x40000 ramoops.console_size=0x20000 ramoops.record_size=0x10000 ramoops.pmsg_size=0x10000 console=ttyHSL0,115200 rdinit=/init"

kmake := "make ARCH=arm CROSS_COMPILE=" + toolchain + " O=" + out

# list recipes
default:
    @just --list

# configure kernel from defconfig
defconfig:
    mkdir -p {{out}}
    {{kmake}} {{defconfig}}

# build kernel zImage and DTBs
build: defconfig
    {{kmake}} -j$(nproc) zImage dtbs 2>&1 | tee {{out}}/build.log
    cp {{out}}/arch/arm/boot/zImage {{out}}/zImage
    cp {{out}}/arch/arm/boot/dts/qcom/msm8909-bq268.dtb {{out}}/msm8909-bq268.dtb
    @ls -lh {{out}}/zImage {{out}}/msm8909-bq268.dtb

# build minimal initramfs (downloads busybox-static from Alpine)
initramfs:
    bash scripts/build-initramfs.sh

# assemble boot.img from existing build artifacts
bootimg-assemble:
    cat {{out}}/zImage {{out}}/msm8909-bq268.dtb > {{out}}/zImage-dtb
    python3 {{mkbootimg}} {{out}}/zImage-dtb {{out}}/initramfs.cpio.gz /dev/null {{out}}/boot.img "{{cmdline}}"
    cp {{out}}/boot.img {{out}}/boot-$(git rev-parse --short HEAD).img
    @ls -lh {{out}}/boot-$(git rev-parse --short HEAD).img

# full build: kernel + initramfs + boot.img
bootimg: build initramfs bootimg-assemble

# flash boot image via fastboot (temporary, does not persist)
fastboot-boot: bootimg
    adb reboot bootloader
    @echo "Waiting for fastboot..."
    fastboot wait-for-device
    fastboot boot {{out}}/boot-$(git rev-parse --short HEAD).img

# flash boot image permanently
fastboot-flash: bootimg
    adb reboot bootloader
    @echo "Waiting for fastboot..."
    fastboot wait-for-device
    fastboot flash boot {{out}}/boot-$(git rev-parse --short HEAD).img
    fastboot reboot

# interactive menuconfig
menuconfig: defconfig
    {{kmake}} menuconfig

# compare built DTB against stock
dtb-diff dtb_stock="docs/fdt_stock.dtb":
    uv run --with fdt python3 scripts/dtb_diff.py {{dtb_stock}} {{out}}/msm8909-bq268.dtb

# show experiment log
experiments:
    git log --oneline --notes=experiments --notes=tasks 1ab88e529c5f..HEAD

# note an experiment outcome on HEAD
note message:
    git notes --ref=experiments append HEAD -m "{{message}}"

# show current tasks
tasks:
    @git notes --ref=tasks show HEAD 2>/dev/null || echo "No tasks on HEAD"

# add a task
task-add description:
    #!/usr/bin/env bash
    existing=$(git notes --ref=tasks show HEAD 2>/dev/null || true)
    if [ -z "$existing" ]; then
        git notes --ref=tasks add HEAD -m "[todo] {{description}}"
    else
        printf '%s\n[todo] %s' "$existing" "{{description}}" | git notes --ref=tasks add -f -F - HEAD
    fi

# mark a task done
task-done pattern:
    #!/usr/bin/env bash
    existing=$(git notes --ref=tasks show HEAD 2>/dev/null || true)
    if [ -z "$existing" ]; then
        echo "No tasks on HEAD"; exit 1
    fi
    echo "$existing" | sed '/\[todo\].*{{pattern}}/s/\[todo\]/[done]/' | \
        sed '/\[in_progress\].*{{pattern}}/s/\[in_progress\]/[done]/' | \
        git notes --ref=tasks add -f -F - HEAD
    git notes --ref=tasks show HEAD

# mark a task in-progress
task-start pattern:
    #!/usr/bin/env bash
    existing=$(git notes --ref=tasks show HEAD 2>/dev/null || true)
    if [ -z "$existing" ]; then
        echo "No tasks on HEAD"; exit 1
    fi
    echo "$existing" | sed '/\[todo\].*{{pattern}}/s/\[todo\]/[in_progress]/' | \
        git notes --ref=tasks add -f -F - HEAD
    git notes --ref=tasks show HEAD

# clean build output
clean:
    rm -rf {{out}}
