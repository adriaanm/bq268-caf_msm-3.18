# BQ268 kernel build recipes
# Run `just` to list available recipes, `just <recipe>` to run one.

toolchain := "/opt/toolchains/gcc-linaro-4.9.4-2017.01-x86_64_arm-linux-gnueabihf/bin/arm-linux-gnueabihf-"
clang := "clang-14 --target=arm-linux-gnueabihf --prefix=" + toolchain + " --gcc-toolchain=/opt/toolchains/gcc-linaro-4.9.4-2017.01-x86_64_arm-linux-gnueabihf -fno-integrated-as"
clang-kcflags := "-gdwarf-2 -Wno-unused-variable -fno-builtin-stpcpy -mno-movt"
strip := "/opt/toolchains/gcc-linaro-4.9.4-2017.01-x86_64_arm-linux-gnueabihf/bin/arm-linux-gnueabihf-strip"
out := "output"
mkbootimg := "tools/mkbootimg/mkbootimg.py"
stock_ramdisk := "boot-data/ramdisk.gz"
defconfig := "bq268_defconfig"
cmdline := "androidboot.hardware=qcom msm_rtb.filter=0x237 ehci-hcd.park=3 androidboot.bootdevice=7824900.sdhci lpm_levels.sleep_disabled=1 androidboot.memcg=true earlyprintk panic=5 ramoops.mem_address=0x9ff00000 ramoops.mem_size=0x40000 ramoops.console_size=0x20000 ramoops.record_size=0x10000 ramoops.pmsg_size=0x10000"

# kernel make commands
kmake := "make ARCH=arm CROSS_COMPILE=" + toolchain + " O=" + out
kmake-clang := "make ARCH=arm CROSS_COMPILE=" + toolchain + " CC='" + clang + "' REAL_CC='" + clang + "' KCFLAGS='" + clang-kcflags + "' O=" + out

# list recipes
default:
    @just --list

# configure kernel from defconfig
defconfig:
    mkdir -p {{out}}
    {{kmake}} {{defconfig}}

# build kernel zImage and device tree blobs
build: defconfig
    {{kmake}} -j$(nproc) zImage dtbs 2>&1 | tee {{out}}/build.log
    cp {{out}}/arch/arm/boot/zImage {{out}}/zImage
    cp {{out}}/arch/arm/boot/dts/qcom/msm8909-bq268.dtb {{out}}/msm8909-bq268.dtb
    @ls -lh {{out}}/zImage {{out}}/msm8909-bq268.dtb

# build kernel with Clang (BROKEN: compiles but doesn't boot)
build-clang: defconfig
    {{kmake-clang}} -j$(nproc) zImage dtbs 2>&1 | tee {{out}}/build.log
    cp {{out}}/arch/arm/boot/zImage {{out}}/zImage
    cp {{out}}/arch/arm/boot/dts/qcom/msm8909-bq268.dtb {{out}}/msm8909-bq268.dtb
    @ls -lh {{out}}/zImage {{out}}/msm8909-bq268.dtb

# build Prima WLAN module
wifi: defconfig
    {{kmake}} KCFLAGS='-Wno-unused-variable' M={{justfile_directory()}}/prima WLAN_ROOT={{justfile_directory()}}/prima MODNAME=wlan CONFIG_PRONTO_WLAN=m modules
    {{strip}} --strip-unneeded -o {{out}}/wlan.ko prima/wlan.ko
    @ls -lh {{out}}/wlan.ko

# build Prima WLAN module with Clang (BROKEN: see build-clang)
wifi-clang: defconfig
    {{kmake-clang}} M={{justfile_directory()}}/prima WLAN_ROOT={{justfile_directory()}}/prima MODNAME=wlan CONFIG_PRONTO_WLAN=m modules
    {{strip}} --strip-unneeded -o {{out}}/wlan.ko prima/wlan.ko
    @ls -lh {{out}}/wlan.ko

# assemble boot.img from existing build artifacts (skip rebuild)
bootimg-assemble:
    cat {{out}}/zImage {{out}}/msm8909-bq268.dtb > {{out}}/zImage-dtb
    rm -rf {{out}}/ramdisk
    mkdir -p {{out}}/ramdisk
    cd {{out}}/ramdisk && gunzip -c {{justfile_directory()}}/{{stock_ramdisk}} | cpio -id 2>/dev/null
    mkdir -p {{out}}/ramdisk/lib/modules
    cp {{out}}/wlan.ko {{out}}/ramdisk/lib/modules/pronto_wlan.ko
    # remove symlinks that the overlay replaces with real files
    cd {{out}}/ramdisk && find {{justfile_directory()}}/ramdisk-overlay -type f -printf '%P\n' | xargs -I{} rm -f {}
    cp -r ramdisk-overlay/. {{out}}/ramdisk/
    grep -q 'init.bq268.rc' {{out}}/ramdisk/init.rc || sed -i '/^import \/init\.${ro\.zygote}\.rc/a import /init.bq268.rc' {{out}}/ramdisk/init.rc
    cd {{out}}/ramdisk && find . | cpio -o -H newc 2>/dev/null | gzip > ../ramdisk-custom.gz
    python3 {{mkbootimg}} {{out}}/zImage-dtb {{out}}/ramdisk-custom.gz /dev/null {{out}}/boot.img "{{cmdline}}"
    cp {{out}}/boot.img {{out}}/boot-$(git rev-parse --short HEAD).img
    @ls -lh {{out}}/boot-$(git rev-parse --short HEAD).img

# create boot.img
bootimg: build wifi bootimg-assemble

# create boot.img with Clang (BROKEN: see build-clang)
bootimg-clang: build-clang wifi-clang bootimg-assemble

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

# push wlan.ko to device (replaces stock pronto_wlan.ko)
wifi-push: wifi
    adb push {{out}}/wlan.ko /data/local/tmp/wlan.ko
    adb shell "su -c 'mount -o remount,rw /vendor && cp /data/local/tmp/wlan.ko /vendor/lib/modules/pronto/pronto_wlan.ko && chmod 644 /vendor/lib/modules/pronto/pronto_wlan.ko'"
    @echo "Module pushed. Reboot to load."

# compare built DTB against stock
dtb-diff dtb_stock="fdt_stock.dtb":
    uv run --with fdt python3 scripts/dtb_diff.py {{dtb_stock}} {{out}}/msm8909-bq268.dtb

# dump a DTB as JSON
dtb-dump file:
    uv run --with fdt python3 scripts/dtb_diff.py --dump {{file}}

# show experiment log (bq268 commits only)
experiments:
    git log --oneline --notes=experiments --notes=tasks 1ab88e529c5f..HEAD

# note an experiment outcome on HEAD (e.g. just note "FAILED: pstore — doesn't boot")
note message:
    git notes --ref=experiments append HEAD -m "{{message}}"

# show current tasks
tasks:
    @git notes --ref=tasks show HEAD 2>/dev/null || echo "No tasks on HEAD"

# add a task (e.g. just task-add "Fix IRQ 97 spam")
task-add description:
    #!/usr/bin/env bash
    existing=$(git notes --ref=tasks show HEAD 2>/dev/null || true)
    if [ -z "$existing" ]; then
        git notes --ref=tasks add HEAD -m "[todo] {{description}}"
    else
        printf '%s\n[todo] %s' "$existing" "{{description}}" | git notes --ref=tasks add -f -F - HEAD
    fi

# mark a task done (matches substring, e.g. just task-done "pstore")
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

# mark a task in-progress (matches substring)
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
