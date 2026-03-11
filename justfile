# BQ268 kernel build recipes
# Run `just` to list available recipes, `just <recipe>` to run one.

toolchain := "/opt/toolchains/gcc-linaro-4.8-2015.06-x86_64_arm-linux-gnueabihf/bin/arm-linux-gnueabihf-"
out := "output"
boot_dir := env("HOME") / "bq268/boot"
defconfig := "bq268_defconfig"

# kernel make with cross-compile defaults
kmake := "make ARCH=arm CROSS_COMPILE=" + toolchain + " O=" + out

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

# create boot.img (zImage with appended DTB + ramdisk with wlan.ko)
bootimg: build wifi
    cat {{out}}/zImage {{out}}/msm8909-bq268.dtb > {{out}}/zImage-dtb
    # repack ramdisk with our wlan.ko
    rm -rf {{out}}/ramdisk
    mkdir -p {{out}}/ramdisk
    cd {{out}}/ramdisk && gunzip -c {{boot_dir}}/ramdisk.gz | cpio -id 2>/dev/null
    mkdir -p {{out}}/ramdisk/vendor/lib/modules/pronto
    cp {{out}}/wlan.ko {{out}}/ramdisk/vendor/lib/modules/pronto/pronto_wlan.ko
    cd {{out}}/ramdisk && find . | cpio -o -H newc 2>/dev/null | gzip > ../ramdisk-custom.gz
    python3 {{boot_dir}}/mkbootimg.py {{out}}/zImage-dtb {{out}}/ramdisk-custom.gz /dev/null {{out}}/boot.img
    @ls -lh {{out}}/boot.img

# flash boot image via fastboot (temporary, does not persist)
fastboot-boot: bootimg
    adb reboot bootloader
    @echo "Waiting for fastboot..."
    fastboot wait-for-device
    fastboot boot {{out}}/boot.img

# flash boot image permanently
fastboot-flash: bootimg
    adb reboot bootloader
    @echo "Waiting for fastboot..."
    fastboot wait-for-device
    fastboot flash boot {{out}}/boot.img
    fastboot reboot

strip := "/opt/toolchains/gcc-linaro-4.8-2015.06-x86_64_arm-linux-gnueabihf/bin/arm-linux-gnueabihf-strip"

# build Prima WLAN module from source (submodule in prima/)
wifi: defconfig
    {{kmake}} M={{justfile_directory()}}/prima WLAN_ROOT={{justfile_directory()}}/prima MODNAME=wlan CONFIG_PRONTO_WLAN=m KCFLAGS=-Wno-unused-variable modules
    {{strip}} --strip-unneeded -o {{out}}/wlan.ko prima/wlan.ko
    @ls -lh {{out}}/wlan.ko

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

# clean build output
clean:
    rm -rf {{out}}
