# nix-images

Ephemeral NixOS images built by GitHub Actions and flashed from a phone, on
stable `nixos-26.05`:

- **Yoga C940 live USB** (x86_64, niri desktop): see below.
- **Raspberry Pi 5 SD card** (aarch64, headless): see further down. Built on
  [`nvmd/nixos-raspberrypi`](https://github.com/nvmd/nixos-raspberrypi).

## Lenovo Yoga C940 live USB

A hybrid UEFI ISO. Root lives in RAM and the stick is only read from, so nothing
touches the laptop's internal disk (Windows stays as it is) and a reboot is a
clean slate.

1. Download `yoga-c940-ephemeral.iso` from the **Releases** page (tag `yoga-...`).
   If the ISO is over GitHub's 2 GB asset limit it is a workflow **artifact**
   on the `build-iso` run instead.
2. Flash the `.iso` as-is to a USB stick with EtchDroid (no unzip).
3. On the laptop: turn **Secure Boot off** in the BIOS, then boot the stick from
   the boot menu (F12).
4. You land in **niri** (Super is `Mod`): `Mod+Return` terminal + tmux, `Mod+D`
   launcher, `Mod+B` Firefox, `Mod+H/L` columns, `Mod+J/K` windows,
   `Mod+U/I` workspaces, `Mod+Shift+/` shows all keys. `nmtui` joins Wi-Fi,
   `pass-cli login` signs in to Proton Pass. No password, no SSH.

**Internal-disk guard:** every non-USB disk (NVMe/SATA/internal SD) and its
partitions is marked read-only at boot (udev rule + `internal-disk-guard.service`),
so nothing in the session can modify the laptop's own drive. USB sticks, including
the one you booted from, are left alone. It stops accidents, not a root user
deliberately running `blockdev --setrw`. Check with `systemctl status
internal-disk-guard` or `lsblk -o NAME,RO`.

Notes: Intel graphics only (the Nvidia GPU is left off). Expect the front
speakers only; the bottom pair needs an init sequence mainline Linux lacks.

## Raspberry Pi 5 SD card

### Get the image onto an SD card (Android + EtchDroid)

1. Open the repo's **Releases** page and download `rpi5-nixos-ephemeral.img.zip`
   (`rpi5-nixos-persistent.img.zip` is a fallback with a normal writable card).
2. Unzip it with the Files app (EtchDroid needs the plain `.img`).
3. In [EtchDroid](https://f-droid.org/packages/eu.depau.etchdroid/), pick the `.img`, pick the SD card in your USB-C reader, flash.
4. Put the card in the Pi 5 and power on.

Every push to `master` or `claude/rpi5-nixos-image` rebuilds both images on a
native arm64 runner and updates that branch's release.

## Ephemeral by design

The ephemeral image keeps the whole root filesystem in RAM; the card is mounted
read-only and only supplies `/nix/store`. Nothing from your session is written
to the card, so power off (or pull the card) and it is gone. Anything you want
to keep lives in Proton Pass or other cloud storage. Consequences: `/tmp`, home
and downloads are limited by RAM, and secrets sit in RAM until power-off.

## Using it

- You are logged in automatically as `pi` on the keyboard/HDMI console, straight
  into tmux. There is **no SSH and no password**; this repo is public.
- Wi-Fi: run `nmtui`.
- Passwords: `pass-cli login` prints a URL, open it on your phone to sign in.
  The CLI keeps its key in the kernel keyring (RAM, cleared on reboot). Needs a
  Proton plan that includes the CLI (Pass Plus/Family/Professional or a bundle).
  If keyring errors appear: `PROTON_PASS_KEY_PROVIDER=fs pass-cli login`
  (fine here, since home is RAM).

## tmux

Prefix is `Ctrl-a`. `prefix ?` opens a fuzzy-searchable list of every key
binding; `prefix Space` opens a grouped quick menu. Edit `modules/tmux.nix`.

## Cloudflare (infra/)

The Cloudflare account is declared in Nix and applied by OpenTofu: PRs get a
read-only plan, merging to `master` applies it. Secrets live in Proton Pass and
are named in `secretspec.toml`. Setup and the token model: [infra/README.md](infra/README.md).

## Checks

`nix flake check` runs nixfmt, statix, deadnix and a NixOS VM test that boots a
VM, attaches tmux, presses `Ctrl-a ?` and reads the key finder off the screen.
CI also runs actionlint and zizmor on the workflows. Format locally with `nix fmt`.

## Changing things

There is no remote access by design. To change the image: edit, push, wait for the
build, reflash. The base is pinned in `flake.lock` and only moves when you run
`nix flake update`.
