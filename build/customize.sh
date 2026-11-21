#!/usr/bin/env bash
# Runs INSIDE the Raspberry Pi OS image (via chroot) during the build.
# Turns a stock Raspberry Pi OS Lite into RetroPi OS.
set -euo pipefail

SRC=/tmp/retropi             # the repo, copied in by build-image.sh
RUSER=retro
RPASS=retro
HOSTNAME_NEW=retropi
RHOME="/home/$RUSER"
RA="$RHOME/.config/retroarch"
BOOT=/boot/firmware; [[ -f $BOOT/config.txt ]] || BOOT=/boot

log() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
export DEBIAN_FRONTEND=noninteractive LC_ALL=C.UTF-8

# ------------------------------------------------------------- packages ---
log "Installing packages"
apt-get update
apt-get -y --no-install-recommends install \
  retroarch cage \
  python3 python3-pygame python3-evdev \
  libgl1-mesa-dri libegl-mesa0 libgles2 \
  pipewire pipewire-pulse wireplumber pulseaudio-utils dbus-user-session \
  samba unzip curl ca-certificates fonts-dejavu-core \
  bluez rfkill network-manager cloud-guest-utils
apt-get -y --no-install-recommends install wsdd || echo "wsdd not available; Windows can still open \\\\retropi\\retro directly"

# ---------------------------------------------------------------- user ---
log "Creating the '$RUSER' user"
OLD="$(getent passwd 1000 | cut -d: -f1 || true)"
if [[ -n "$OLD" && "$OLD" != "$RUSER" ]]; then
  usermod -l "$RUSER" -d "$RHOME" -m "$OLD"
  groupmod -n "$RUSER" "$OLD" 2>/dev/null || true
fi
id "$RUSER" >/dev/null 2>&1 || useradd -m -u 1000 -s /bin/bash "$RUSER"
echo "$RUSER:$RPASS" | chpasswd
for g in adm dialout cdrom sudo audio video plugdev games users input render netdev gpio i2c spi bluetooth; do
  getent group "$g" >/dev/null && usermod -aG "$g" "$RUSER"
done
echo "$RUSER ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/010_retro-nopasswd
chmod 440 /etc/sudoers.d/010_retro-nopasswd

# Skip Raspberry Pi OS's "create a user" first-boot steps: the user exists already
systemctl disable userconfig.service 2>/dev/null || true
rm -f /etc/ssh/sshd_config.d/rename_user.conf

# --------------------------------------------------------------- files ---
log "Installing RetroPi files"
cp -a "$SRC/files/rootfs/." /
chmod 755 /usr/local/bin/retro-* /usr/local/sbin/retro-*
cp "$SRC/files/boot/retro-wifi.txt" "$BOOT/retro-wifi.txt"

mkdir -p /usr/share/fonts/truetype/retropi
cp "$SRC"/fonts/*.ttf /usr/share/fonts/truetype/retropi/ 2>/dev/null || echo "custom fonts missing; using fallback font"

systemctl enable retro-wifi.service retro-boot-check.service
systemctl enable ssh
systemctl enable smbd nmbd 2>/dev/null || true
systemctl enable wsdd 2>/dev/null || true
systemctl --global enable pipewire.socket pipewire-pulse.socket wireplumber.service 2>/dev/null || true
for u in NetworkManager-wait-online.service apt-daily.timer apt-daily-upgrade.timer man-db.timer; do
  systemctl disable "$u" 2>/dev/null || true
done

# --------------------------------------------------------- game folders ---
for d in nes snes gb gbc gba n64 megadrive mastersystem gamegear psx pcengine atari2600 arcade; do
  mkdir -p "$RHOME/retro/roms/$d"
done
mkdir -p "$RHOME/retro"/{bios,saves,states,screenshots,boxart} "$RHOME/.cache/retro" "$RHOME/.config/retro-os"
cat > "$RHOME/retro/README.txt" <<'EOF'
RetroPi OS - where things go
============================
roms/<system>/  your games (zipped is fine for cartridge consoles)
                nes snes gb gbc gba n64 megadrive mastersystem gamegear
                psx (.chd .cue .pbp .m3u)  pcengine  atari2600
                arcade (FinalBurn Neo romsets, .zip)
bios/           BIOS files. Optional: PlayStation works without one.
boxart/<system>/ cover pictures: name a .png exactly like the game file
saves/ states/  your saves
After copying, choose Settings > Look for new games (or restart).
EOF

# ---------------------------------------------------------------- cores ---
log "Downloading emulator cores"
mkdir -p "$RA"/{cores,autoconfig}
BB="https://buildbot.libretro.com/nightly/linux/aarch64/latest"
CORES=(fceumm snes9x gambatte mgba mupen64plus_next genesis_plus_gx pcsx_rearmed mednafen_pce_fast stella2014 fbneo)
FAILED=()
for c in "${CORES[@]}"; do
  if curl -fsSL --retry 4 --retry-delay 5 -o "/tmp/$c.zip" "$BB/${c}_libretro.so.zip" \
     && unzip -o -q "/tmp/$c.zip" -d "$RA/cores"; then
    echo "  ok  $c"
  else
    echo "  FAILED  $c"; FAILED+=("$c")
  fi
  rm -f "/tmp/$c.zip"
done
if (( ${#FAILED[@]} > 3 )); then
  echo "Too many cores failed to download (${FAILED[*]}). Stopping so you don't get a half-working image."
  exit 1
fi

if curl -fsSL --retry 4 -o /tmp/autoconfig.zip "https://buildbot.libretro.com/assets/frontend/autoconfig.zip"; then
  unzip -o -q /tmp/autoconfig.zip -d "$RA/autoconfig"
  if [[ -d "$RA/autoconfig/autoconfig/udev" ]]; then
    cp -a "$RA/autoconfig/autoconfig/." "$RA/autoconfig/" && rm -rf "$RA/autoconfig/autoconfig"
  fi
  rm -f /tmp/autoconfig.zip
fi

# ------------------------------------------------------------ retroarch ---
log "Configuring RetroArch"
cat > "$RA/retroarch.cfg" <<EOF
libretro_directory = "$RA/cores"
joypad_autoconfig_dir = "$RA/autoconfig"
system_directory = "$RHOME/retro/bios"
savefile_directory = "$RHOME/retro/saves"
savestate_directory = "$RHOME/retro/states"
screenshot_directory = "$RHOME/retro/screenshots"
rgui_browser_directory = "$RHOME/retro/roms"
video_driver = "gl"
video_fullscreen = "true"
video_vsync = "true"
video_threaded = "false"
video_smooth = "false"
video_shader_enable = "false"
video_aspect_ratio_auto = "true"
video_font_enable = "true"
audio_driver = "pulse"
audio_latency = "64"
audio_sync = "true"
input_joypad_driver = "udev"
input_autodetect_enable = "true"
input_menu_toggle_gamepad_combo = "3"
all_users_control_menu = "true"
menu_driver = "rgui"
rgui_aspect_ratio_lock = "1"
pause_nonactive = "false"
quit_on_close_content = "1"
quit_press_twice = "false"
savestate_auto_save = "true"
savestate_auto_load = "true"
savestate_thumbnail_enable = "true"
sort_savefiles_enable = "true"
sort_savestates_enable = "true"
rewind_enable = "false"
run_ahead_enabled = "false"
config_save_on_exit = "true"
notification_show_autoconfig = "true"
EOF

# ------------------------------------------------------ auto-start setup ---
log "Setting up boot straight into the dashboard"
mkdir -p /etc/systemd/system/getty@tty1.service.d
cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $RUSER --noclear %I \$TERM
EOF
systemctl set-default multi-user.target

PROFILE="$RHOME/.bash_profile"
cat > "$PROFILE" <<'EOF'
[ -f "$HOME/.profile" ] && . "$HOME/.profile"
# Start RetroPi on the TV. To stop this (over SSH): touch ~/.retro-noauto
if [ "$(tty)" = "/dev/tty1" ] && [ -z "${WAYLAND_DISPLAY:-}" ] && [ ! -f "$HOME/.retro-noauto" ]; then
  /usr/local/bin/retro-session
fi
EOF

# ------------------------------------------------------------- hostname ---
echo "$HOSTNAME_NEW" > /etc/hostname
if grep -q '^127\.0\.1\.1' /etc/hosts; then
  sed -i "s/^127\.0\.1\.1.*/127.0.1.1\t$HOSTNAME_NEW/" /etc/hosts
else
  printf '127.0.1.1\t%s\n' "$HOSTNAME_NEW" >> /etc/hosts
fi

# ---------------------------------------------------------------- samba ---
log "Setting up the network share"
cat >> /etc/samba/smb.conf <<EOF

[retro]
   comment = RetroPi games, BIOS and saves
   path = $RHOME/retro
   browseable = yes
   read only = no
   guest ok = no
   valid users = $RUSER
   force user = $RUSER
   create mask = 0644
   directory mask = 0755
EOF
printf '%s\n%s\n' "$RPASS" "$RPASS" | smbpasswd -a -s "$RUSER"

# ----------------------------------------------------------- boot tuning ---
log "Tuning boot"
{
  echo ""
  echo "# --- RetroPi OS ---"
  echo "[all]"
  grep -q '^dtoverlay=vc4-kms-v3d' "$BOOT/config.txt" || echo "dtoverlay=vc4-kms-v3d"
  grep -q '^max_framebuffers=' "$BOOT/config.txt" || echo "max_framebuffers=2"
  echo "disable_splash=1"
  echo "boot_delay=0"
  echo "arm_boost=1"
} >> "$BOOT/config.txt"

CMDLINE="$BOOT/cmdline.txt"
sed -i -E '1 s/ loglevel=[0-9]+//' "$CMDLINE"
for t in quiet loglevel=3 logo.nologo vt.global_cursor_default=0 consoleblank=0; do
  grep -qE "(^| )${t//./\\.}( |$)" "$CMDLINE" || sed -i "1 s|\$| $t|" "$CMDLINE"
done

# ------------------------------------------------------------- finish ---
chown -R "$RUSER:$RUSER" "$RHOME"
apt-get clean
rm -rf /var/lib/apt/lists/* /tmp/*.zip

echo
echo "RetroPi OS customization finished."
(( ${#FAILED[@]} )) && echo "Note: these cores could not be downloaded: ${FAILED[*]}"
exit 0
