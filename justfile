# BQ268 kernel build recipes
# Run `just` to list available recipes, `just <recipe>` to run one.

toolchain := "/opt/toolchains/gcc-linaro-4.8-2015.06-x86_64_arm-linux-gnueabihf/bin/arm-linux-gnueabihf-"
out := "output"
boot_dir := env("HOME") / "bq268/boot"
defconfig := "bq268_defconfig"

# kernel make with cross-compile defaults
# LOCALVERSION= suppresses the git "+" suffix so version magic matches stock (3.18.71-perf)
kmake := "make ARCH=arm CROSS_COMPILE=" + toolchain + " O=" + out + " LOCALVERSION="

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

# create boot.img (zImage with appended DTB + stock ramdisk)
bootimg: build
    cat {{out}}/zImage {{out}}/msm8909-bq268.dtb > {{out}}/zImage-dtb
    python3 {{boot_dir}}/mkbootimg.py {{out}}/zImage-dtb {{boot_dir}}/ramdisk.gz /dev/null {{out}}/boot.img
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
