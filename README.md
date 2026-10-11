# nix-images

Headless NixOS SD card image for the Raspberry Pi 5, built by GitHub Actions
and flashed from a phone. Built on [`nvmd/nixos-raspberrypi`](https://github.com/nvmd/nixos-raspberrypi)
(stable `nixos-26.05`); no desktop environment, just a lean base plus tmux.

## Get the image onto an SD card (Android + EtchDroid)

1. Open the repo's **Releases** page and download `rpi5-nixos.img.zip`.
2. Unzip it with the Files app (EtchDroid needs the plain `.img`).
3. In [EtchDroid](https://f-droid.org/packages/eu.depau.etchdroid/), pick the `.img`, pick the SD card in your USB-C reader, flash.
4. Put the card in the Pi 5 and power on.

Every push to `master` or `claude/rpi5-nixos-image` rebuilds the image on a
native arm64 runner and updates that branch's release.

## First login

- Console (keyboard + HDMI): user `pi`, temporary password `changeme`.
- SSH: key only. Add your public key to `modules/base.nix`
  (`users.users.pi.openssh.authorizedKeys.keys`) and delete `initialPassword`.
  This repo is public: never commit secrets (Wi-Fi passwords etc.).

## tmux

Prefix is `Ctrl-a`. `prefix ?` opens a fuzzy-searchable list of every key
binding; `prefix Space` opens a grouped quick menu. Edit `modules/tmux.nix`.

## Checks

`nix flake check` runs nixfmt, statix, deadnix and a NixOS VM test that boots a
VM, attaches tmux, presses `Ctrl-a ?` and reads the key finder off the screen.
CI also runs actionlint and zizmor on the workflows. Format locally with `nix fmt`.

## Updating

The base is pinned in `flake.lock`; it only changes when you run `nix flake update`.
After the first flash, update a running Pi without reflashing:

    nixos-rebuild switch --flake .#rpi5 --target-host pi@rpi5 --use-remote-sudo
