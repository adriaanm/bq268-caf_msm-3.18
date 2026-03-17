#!/bin/bash
# Build minimal initramfs with busybox from Alpine Linux
# Output: output/initramfs.cpio.gz
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
OUT="$ROOT_DIR/output"
ROOTFS_SRC="$ROOT_DIR/rootfs"
INITRAMFS="$OUT/initramfs"

BUSYBOX_URL="https://dl-cdn.alpinelinux.org/alpine/v3.21/main/armhf/busybox-static-1.37.0-r14.apk"

echo "=== Building minimal initramfs ==="

mkdir -p "$OUT"

# --- Download busybox-static from Alpine ---
BUSYBOX_APK="$OUT/busybox-static-1.37.0-r14.apk"
if [ ! -f "$BUSYBOX_APK" ]; then
    echo "Downloading busybox-static..."
    curl -sL -o "$BUSYBOX_APK" "$BUSYBOX_URL"
fi

# --- Build initramfs directory ---
echo "Creating initramfs layout..."
rm -rf "$INITRAMFS"
mkdir -p "$INITRAMFS"/{bin,sbin,usr/bin,dev,proc,sys,tmp,etc,lib/modules}

# Extract busybox binary
echo "Extracting busybox..."
tar xzf "$BUSYBOX_APK" -C "$OUT" bin/busybox.static 2>/dev/null || \
    gzip -dc "$BUSYBOX_APK" | tar xf - -C "$OUT" bin/busybox.static 2>/dev/null || {
    echo "ERROR: Failed to extract busybox from APK"
    exit 1
}
cp "$OUT/bin/busybox.static" "$INITRAMFS/bin/busybox"
chmod 755 "$INITRAMFS/bin/busybox"

# Create busybox symlinks
echo "Creating busybox applet symlinks..."
# Common applets needed for a useful debug shell
for applet in sh ash ls cat echo mkdir mount umount sleep \
    cp mv rm ln chmod chown grep sed awk cut head tail \
    ps kill dmesg reboot poweroff halt \
    ifconfig ip route ping \
    vi less more wc sort uniq tr tee \
    devmem hexdump dd free uptime hostname \
    find xargs printf test expr seq \
    tar gzip gunzip df du stat id whoami \
    setsid cttyhack getty login; do
    ln -sf busybox "$INITRAMFS/bin/$applet"
done

# /init
cp "$ROOTFS_SRC/init" "$INITRAMFS/init"
chmod 755 "$INITRAMFS/init"

# dump-registers script
cp "$ROOTFS_SRC/dump-registers.sh" "$INITRAMFS/usr/bin/dump-registers"
chmod 755 "$INITRAMFS/usr/bin/dump-registers"

# reboot-bootloader (pre-compiled static binary)
cp "$ROOT_DIR/tools/reboot-bootloader" "$INITRAMFS/sbin/reboot-bootloader"
chmod 755 "$INITRAMFS/sbin/reboot-bootloader"

# /etc/inittab
cp "$ROOTFS_SRC/etc/inittab" "$INITRAMFS/etc/inittab"

# Minimal /etc
cat > "$INITRAMFS/etc/profile" << 'EOF'
export PATH=/bin:/sbin:/usr/bin:/usr/sbin
export PS1='bq268-caf# '
alias ll='ls -la'
alias dump='dump-registers'
EOF

# --- Pack cpio ---
echo "Packing initramfs..."
cd "$INITRAMFS"
find . | cpio -o -H newc 2>/dev/null | gzip > "$OUT/initramfs.cpio.gz"
echo "Built: $OUT/initramfs.cpio.gz ($(du -h "$OUT/initramfs.cpio.gz" | cut -f1))"
