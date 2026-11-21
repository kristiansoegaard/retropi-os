#!/usr/bin/env bash
# Builds retropi-os.img.xz from the latest Raspberry Pi OS Lite (64-bit).
# Runs on GitHub Actions automatically, or on any Linux PC with:
#   sudo apt install qemu-user-static binfmt-support parted e2fsprogs xz-utils curl
#   sudo bash build/build-image.sh
set -euo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${WORK:-$REPO/work}"
OUT="${OUT:-$REPO/out}"
EXTRA_MB="${EXTRA_MB:-3072}"     # room for emulators and packages; expands to the full card on first boot
BASE_URL="https://downloads.raspberrypi.com/raspios_lite_arm64_latest"
IMG="$WORK/retropi-os.img"
MNT="$WORK/mnt"

log() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
[[ $EUID -eq 0 ]] || { echo "Run with sudo"; exit 1; }
mkdir -p "$WORK" "$OUT" "$MNT"

LOOP=""
cleanup() (   # runs in a subshell so "set +e" doesn't leak into the build
  set +e
  sync
  for m in "$MNT/boot/firmware" "$MNT/boot" "$MNT/dev/pts" "$MNT/dev" "$MNT/proc" "$MNT/sys" "$MNT/run" "$MNT"; do
    mountpoint -q "$m" && { umount "$m" 2>/dev/null || umount -l "$m"; }
  done
  [[ -n "$LOOP" ]] && losetup -d "$LOOP" 2>/dev/null
  true
)
trap cleanup EXIT

# ------------------------------------------------------------ download ---
log "Downloading Raspberry Pi OS Lite (64-bit)"
REAL_URL="$(curl -fsSIL -o /dev/null -w '%{url_effective}' "$BASE_URL")"
echo "Base image: $REAL_URL"
curl -fL --retry 4 --retry-delay 5 -o "$WORK/base.img.xz" "$REAL_URL"
if curl -fsSL -o "$WORK/base.sha256" "$REAL_URL.sha256"; then
  (cd "$WORK" && echo "$(awk '{print $1}' base.sha256)  base.img.xz" | sha256sum -c -)
else
  echo "No checksum published next to the image; continuing."
fi
basename "$REAL_URL" > "$OUT/base-image.txt"

log "Unpacking and enlarging the image"
xz -dc "$WORK/base.img.xz" > "$IMG"
rm -f "$WORK/base.img.xz"
truncate -s "+${EXTRA_MB}M" "$IMG"
parted -s "$IMG" resizepart 2 100%
LOOP="$(losetup -fP --show "$IMG")"
sleep 1
e2fsck -fy "${LOOP}p2" || [[ $? -le 1 ]]
resize2fs "${LOOP}p2"

# --------------------------------------------------------------- mount ---
log "Mounting"
mount "${LOOP}p2" "$MNT"
if [[ -d "$MNT/boot/firmware" ]]; then BOOTMNT="$MNT/boot/firmware"; else BOOTMNT="$MNT/boot"; fi
mount "${LOOP}p1" "$BOOTMNT"
mount --bind /dev "$MNT/dev"
mount --bind /dev/pts "$MNT/dev/pts"
mount -t proc proc "$MNT/proc"
mount -t sysfs sys "$MNT/sys"
mount -t tmpfs tmpfs "$MNT/run"

# Network inside the chroot, and don't let packages start services there
RESOLV_BAK=""
if [[ -e "$MNT/etc/resolv.conf" || -L "$MNT/etc/resolv.conf" ]]; then
  RESOLV_BAK="$MNT/etc/resolv.conf.retropi-bak"
  mv "$MNT/etc/resolv.conf" "$RESOLV_BAK"
fi
cp -L /etc/resolv.conf "$MNT/etc/resolv.conf"
printf '#!/bin/sh\nexit 101\n' > "$MNT/usr/sbin/policy-rc.d"
chmod 755 "$MNT/usr/sbin/policy-rc.d"

# ------------------------------------------------------------- customize ---
log "Fetching fonts"
mkdir -p "$REPO/fonts"
GF="https://raw.githubusercontent.com/google/fonts/main/ofl"
for f in atkinsonhyperlegible/AtkinsonHyperlegible-Regular.ttf atkinsonhyperlegible/AtkinsonHyperlegible-Bold.ttf archivoblack/ArchivoBlack-Regular.ttf; do
  curl -fsSL --retry 3 -o "$REPO/fonts/$(basename "$f")" "$GF/$f" || echo "font download failed: $f (fallback font will be used)"
done

log "Customizing (this is the long part)"
rm -rf "$MNT/tmp/retropi"
mkdir -p "$MNT/tmp/retropi"
cp -a "$REPO/files" "$REPO/build" "$REPO/fonts" "$MNT/tmp/retropi/"
chroot "$MNT" /bin/bash /tmp/retropi/build/customize.sh

# --------------------------------------------------------------- finish ---
log "Cleaning up"
rm -rf "$MNT/tmp/retropi" "$MNT/usr/sbin/policy-rc.d"
rm -f "$MNT/etc/resolv.conf"
[[ -n "$RESOLV_BAK" ]] && mv "$RESOLV_BAK" "$MNT/etc/resolv.conf"
rm -f "$MNT/root/.bash_history"
fstrim -v "$MNT" || true            # frees deleted blocks so the image compresses well
cleanup
trap - EXIT
LOOP=""

log "Compressing (several minutes)"
xz -T0 -6 -f "$IMG"
mv "$IMG.xz" "$OUT/retropi-os.img.xz"
(cd "$OUT" && sha256sum retropi-os.img.xz > retropi-os.img.xz.sha256)
ls -lh "$OUT"
echo "Done: $OUT/retropi-os.img.xz"
