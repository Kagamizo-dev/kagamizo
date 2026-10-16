# nix-images

Ephemeral NixOS images for specific devices, built by GitHub Actions and flashed
from a phone. Stable `nixos-26.05` base, pinned in `flake.lock`.

## Devices

| Device | Directory | Arch | Image | Status |
|---|---|---|---|---|
| Lenovo Yoga C940-14IIL | `devices/yoga-c940` | x86_64 | live USB ISO, niri desktop | active |
| Raspberry Pi 5 | `devices/rpi5` | aarch64 | SD card image, headless | paused (beta only) |

Shared building blocks live in `profiles/` (tmux, Proton Pass CLI, niri desktop,
a welcome screen). A device is a directory under `devices/` that pulls in the
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
4. You land in **niri** with a clickable bar at the top (Apps, Terminal, Firefox, Help,
   volume, Wi-Fi, battery, Quit) and niri's own list of important keys on screen
   (press Escape to close it). The first terminal opens on a **welcome screen**
   (fastfetch summary, a soft system check, the keys). Run `welcome` any time to see it
   again. `Mod` is the Super (Windows) key: `Mod+D` launcher, `Mod+B` Firefox,
   `Mod+Return` terminal, `Mod+H/L` columns, `Mod+Shift+/` every niri key.
   `nmtui` joins Wi-Fi, `pass-cli login` signs in to Proton Pass. No password, no SSH.

### First-run setup (runs by itself in the first terminal; `setup` re-runs it)

1. **Internet**: plug the phone in with a USB cable and turn on USB tethering
   (Pixel: Settings > Network & internet > Hotspot & tethering > USB tethering).
   No Wi-Fi password is baked into the image.
2. **Proton Pass**: `pass-cli login` prints a link, open it on the phone.
3. **Wi-Fi**: every Login item titled `Wi-Fi: <network name>` in the vault `yoga`
   (password = the Wi-Fi password) is saved as a known network. Unplug the phone
   once Wi-Fi is up.
4. **AI agents**: the Login item `OpenRouter` in the vault `yoga` (password = the
   API key) is loaded into memory and two [Pi](https://github.com/badlogic/pi-mono)
   coding agents start in tmux windows `agent-1` and `agent-2`, using
   `openrouter` / `deepseek/deepseek-v4-flash`.

Secrets only ever live in memory; nothing is written to the USB stick.

The session never mounts the laptop's internal disk automatically, so Windows is left
alone as long as you don't mount or write to it yourself.

Wallpaper: `profiles/wallpaper/japan-countryside-4k.png` (drawn by `scripts/make-wallpaper.py`), set at startup by `swaybg`
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
a waybar config check, and VM tests (tmux key finder, niri desktop + welcome screen). CI also runs
actionlint and zizmor on the workflows, and the Yoga pipeline boots the finished
ISO under UEFI as a USB stick. Format locally with `nix fmt`.

Images contain no secrets: the repository is public.

## Changing things

There is no remote access by design. To change an image: commit to `beta`, wait for
the pipeline, reflash. `stable` follows by itself when everything passes. The base
only moves when you run `nix flake update`.
