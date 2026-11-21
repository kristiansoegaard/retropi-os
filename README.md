# RetroPi OS

A retro gaming console OS for the Raspberry Pi 4 and Pi 400. It boots straight into its own game dashboard: pick a console, pick a game, play. 13 consoles are set up and ready, from the NES to the PlayStation.

## Get the image file (one time, about an hour, mostly waiting)

GitHub builds the image for you on its computers, for free. You only click buttons.

1. Make a free account at [github.com](https://github.com) if you don't have one.
2. Click **+** (top right) and choose **New repository**. Name it `retropi-os`, choose **Public**, and click **Create repository**.
3. On the next page, click the link **uploading an existing file**. Unzip `retropi-os.zip` on your computer, open the folder, select everything inside it (including the `.github` folder) and drag it onto the page. Click **Commit changes**.
   - On a Mac, the `.github` folder is hidden. Press Cmd + Shift + . (period) in Finder to show it.
4. Check that the file `.github/workflows/build-image.yml` appears in your repository. If it's missing, click **Add file > Create new file**, type `.github/workflows/build-image.yml` as the name, paste in the contents of that file, and commit.
5. Open the **Actions** tab. If GitHub asks, click the button to enable workflows. Choose **Build RetroPi OS image** on the left, then **Run workflow** and the green **Run workflow** button.
6. Wait for the green tick (usually 30 to 60 minutes). If you picked the `ubuntu-24.04` build machine it takes longer.
7. Go back to your repository's main page. Under **Releases** on the right, open the newest one and download **retropi-os.img.xz** (about 1.5 GB).

## Put it on the SD card

1. Open [Raspberry Pi Imager](https://www.raspberrypi.com/software/).
2. Device: **Raspberry Pi 4**. Operating system: scroll down to **Use custom** and pick `retropi-os.img.xz`. Storage: your SD card.
3. When Imager asks about OS customisation, choose **No**. RetroPi sets itself up.
4. **Wi-Fi** (skip this if you use a network cable): when Imager finishes, take the SD card out and put it back into your computer. Open the drive called **bootfs**, open `retro-wifi.txt`, type your Wi-Fi name after `SSID=` and the password after `PASSWORD=`, and save.
5. Put the card in the Pi, plug in a controller and the TV, and switch on. The first start takes a minute or two longer while it sets up.

## Adding games

The easiest way is a USB stick:

1. On the stick, make a folder named `roms` and put your games in it.
2. Plug the stick into the Pi while the dashboard is showing. It copies the games, sorts them into the right consoles and tells you when you can unplug it.

Folders like `roms/snes` or `roms/psx` on the stick are kept as they are. Game files placed loose in `roms` are sorted by type. Files that could belong to several consoles (like `.zip` or `.bin`) go to `roms/unsorted`. Move them to the right folder over the network.

Over the network instead: open `\\retropi\retro` in Windows File Explorer, or `smb://retropi.local/retro` on a Mac. The user is `retro` and the password is `retro`. Then choose **Settings > Look for new games**.

| Folder | Console | File types |
|---|---|---|
| nes | NES | .nes .fds .zip |
| snes | Super Nintendo | .sfc .smc .zip |
| gb / gbc / gba | Game Boy family | .gb / .gbc / .gba .zip |
| n64 | Nintendo 64 | .z64 .n64 .v64 .zip |
| megadrive | Mega Drive / Genesis | .md .gen .bin .zip |
| mastersystem / gamegear | Sega 8-bit | .sms / .gg .zip |
| psx | PlayStation | .chd .cue .pbp .m3u |
| pcengine | PC Engine | .pce .zip |
| atari2600 | Atari 2600 | .a26 .bin .zip |
| arcade | Arcade (FinalBurn Neo) | .zip romsets |

PlayStation games run without a BIOS. Adding a real one (`scph5501.bin` in the `bios` folder) improves compatibility. Box art downloads automatically when the console is online, for games whose files have their usual names. You can add your own: a `.png` named exactly like the game file, in `boxart/<console>/`.

## Controls

| | |
|---|---|
| D-pad or stick | Move |
| A | Open, play |
| B | Back |
| Y | Add or remove a favorite |
| L / R | Jump to the next or previous letter |
| Hold Start + Select (1 second) | Leave the game and return to the dashboard |
| L + R + Start + Select | In-game menu: save states, controls, video settings |

Your place in a game is saved automatically when you leave it, and you continue from there next time. Favorites and recently played games get their own spots on the home screen.

Bluetooth controllers: **Settings > Pair a Bluetooth controller**, then put the controller in pairing mode.

## Good to know

- N64 is the most demanding console. Lighter games run well; some heavier ones will stutter on any Pi 4.
- The login is user `retro`, password `retro` (for the network share and SSH). To change it, connect with `ssh retro@retropi.local` and run `passwd` and `sudo smbpasswd retro`.
- If something goes wrong, the logs are in `/home/retro/.cache/retro/` (reachable over SSH).
- To stop the dashboard from starting (for tinkering): `touch ~/.retro-noauto` over SSH, then reboot. Delete the file to undo.

## Building on your own Linux PC instead

```
sudo apt install qemu-user-static binfmt-support parted e2fsprogs xz-utils curl
sudo bash build/build-image.sh
```

The image appears in `out/`.

## What's inside

Raspberry Pi OS Lite (64-bit) as the base, RetroArch with libretro emulator cores for the games, and a dashboard written in Python with pygame. The cores were picked for the Pi 4: FCEUmm, Snes9x, Gambatte, mGBA, Mupen64Plus-Next, Genesis Plus GX, PCSX ReARMed, Beetle PCE Fast, Stella 2014 and FinalBurn Neo.
