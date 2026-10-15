# nix-images

Ephemeral NixOS images for specific devices, built by GitHub Actions and flashed
from a phone. Stable `nixos-26.05` base, pinned in `flake.lock`.

## Devices

| Device | Directory | Arch | Image | Status |
|---|---|---|---|---|
| Lenovo Yoga C940-14IIL | `devices/yoga-c940` | x86_64 | live USB ISO, niri desktop | active |
| Raspberry Pi 5 | `devices/rpi5` | aarch64 | SD card image, headless | paused (beta only) |

Shared building blocks live in `profiles/` (tmux, Proton Pass CLI, niri desktop,
internal-disk guard). A device is a directory under `devices/` that pulls in the
profiles it wants and adds its own hardware settings (firmware, kernel params).
To add a device: copy a directory under `devices/`, register it in
`nixosConfigurations` in `flake.nix`, and add a pipeline like
`.github/workflows/yoga-c940.yml`.

## Branches: beta and stable

- **`beta`**: where work happens. Every push is checked, built, boot-tested and
  published as a **pre-release** (`yoga-c940-beta`).
- **`stable`**: production. Nobody pushes to it by hand. The pipeline moves it
  forward to a `beta` commit only after **all** flake checks and the ISO boot test
  passed, and publishes that ISO as the `yoga-c940-stable` release.

Stable download (always the last build that passed everything):

    https://github.com/presentatou/nix-images/releases/download/yoga-c940-stable/yoga-c940-ephemeral.iso

## Lenovo Yoga C940-14IIL live USB

A hybrid UEFI ISO. Root lives in RAM and the stick is only read from, so a reboot
is a clean slate and nothing is written to the laptop.

1. On your phone download `yoga-c940-ephemeral.iso` from the link above (or the
   `yoga-c940-beta` pre-release for the in-progress build).
2. Flash the `.iso` as-is to a USB stick with
   [EtchDroid](https://f-droid.org/packages/eu.depau.etchdroid/) (no unzip).
3. On the laptop: turn **Secure Boot off** in the BIOS and put USB first in the
   boot order (or use the boot menu, F12).
4. You land in **niri** (Super is `Mod`): `Mod+Return` terminal + tmux, `Mod+D`
   launcher, `Mod+B` Firefox, `Mod+H/L` columns, `Mod+J/K` windows,
   `Mod+U/I` workspaces, `Mod+Shift+/` shows all keys. `nmtui` joins Wi-Fi,
   `pass-cli login` signs in to Proton Pass. No password, no SSH.

**Internal-disk guard:** every non-USB disk (NVMe/SATA/internal SD) and its
partitions is marked read-only at boot (udev rule + `internal-disk-guard.service`),
so nothing in the session can modify the laptop's own drive, Windows included.
USB sticks, including the one you booted from, are left alone. It stops accidents,
not a root user deliberately running `blockdev --setrw`. Verify with
`lsblk -o NAME,RO` (internal disk `1`, stick `0`).

Wallpaper: `profiles/wallpaper/cherry-blossom-night.png`, set at startup by `swaybg`
(niri draws no wallpaper itself). To change it, replace that file (keep it a PNG under
~8 MB; the build checks) and push to `beta`.

Hardware notes: Intel graphics only. The image carries only the firmware this
laptop needs (Intel AX201 Wi-Fi/Bluetooth, i915, Sound Open Firmware), which keeps
the ISO under GitHub's 2 GB release-asset limit. Expect the front speakers only;
the bottom pair needs an init sequence mainline Linux lacks.

## Raspberry Pi 5 SD card (paused)

Built from the `beta` branch only, as the `rpi5-beta` pre-release
(`rpi5-nixos-ephemeral.img.zip`; `rpi5-nixos-persistent.img.zip` is a fallback with a
normal writable card). Unzip with the Files app, then flash the `.img` with
EtchDroid. Same ephemeral idea: root in RAM, the card mounted read-only. Headless:
auto-login on the console straight into tmux.

## tmux and Proton Pass

Prefix is `Ctrl-a`. `prefix ?` opens a fuzzy-searchable list of every key binding;
`prefix Space` opens a grouped quick menu. Edit `profiles/tmux.nix`.

`pass-cli login` prints a URL to open on your phone. The CLI keeps its key in the
kernel keyring (RAM, cleared on reboot). It needs a Proton plan that includes the
CLI (Pass Plus/Family/Professional or a bundle). If keyring errors appear:
`PROTON_PASS_KEY_PROVIDER=fs pass-cli login` (fine here, since home is RAM).

## Checks

`nix flake check` runs nixfmt, statix, deadnix, a niri config validation, and NixOS
VM tests (tmux key finder, niri desktop, internal-disk guard). CI also runs
actionlint and zizmor on the workflows, and the Yoga pipeline boots the finished
ISO under UEFI as a USB stick. Format locally with `nix fmt`.

Images contain no secrets: the repository is public.

## Changing things

There is no remote access by design. To change an image: commit to `beta`, wait for
the pipeline, reflash. `stable` follows by itself when everything passes. The base
only moves when you run `nix flake update`.
