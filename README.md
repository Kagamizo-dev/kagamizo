# kagamizo

Kagamizo as code: ephemeral NixOS images for specific devices (built by GitHub
Actions and flashed from a phone), the Cloudflare account, the Proton Pass
vaults, the GitHub organization and every account they run on. Stable
`nixos-26.05` base, pinned in `flake.lock`.

## Devices

| Device | Directory | Arch | Image | Status |
|---|---|---|---|---|
| Lenovo Yoga C940-14IIL | `modules/yoga-c940` | x86_64 | live USB ISO, niri desktop | active |
| Raspberry Pi 5 | `modules/rpi5` | aarch64 | SD card image, headless | paused |

Shared building blocks are modules too (`tmux`, `tools`, `desktop`, `welcome`,
`setup`), each exporting a `nixosModules.<name>`. A device module assembles the
ones it wants and adds its own hardware settings (firmware, kernel params). To
add a device: copy `modules/yoga-c940`, and add a pipeline like
`.github/workflows/yoga-c940.yml`.

## Layout

Everything is a module under `modules/`, loaded by
[import-tree](https://github.com/vic/import-tree) into
[flake-parts](https://flake.parts) (the dendritic pattern). A module is one
self-contained unit: it declares its own account, plan and capabilities, its
secrets (`secrets.profiles`, merged into `secretspec.toml`), its packages,
checks and deployment targets, and keeps its own files.

- Every `.nix` file in `modules/` is a flake-parts module.
- Anything under a path starting with `_` is not: NixOS modules (`_nixos.nix`),
  VM tests (`_test.nix`), assets (`_assets/`), scripts (`_scripts/`), catalogs
  (`_json/`), OpenTofu layers (`_zones.nix`).
- `modules/_lib/` holds what modules share: `cli.nix` (every CLI call typed
  against the catalogs), `types.nix` (nix-effects types), `secret.nix`.

At the top level there is only the flake, the generated `secretspec.toml`
(secretspec reads it from there), the docs and `.github/`.

```
modules/
├─ _lib/          cli.nix, types.nix, secret.nix
├─ core/          systems, formatter
├─ accounts/      the account, plan and capability types; `signup`
├─ identity/      entities, domains, mailboxes (nix-effects)
├─ proton/        vaults, agent tokens, `proton`; renders secretspec.toml
├─ cloudflare/    account, tokens, `bootstrap`, `infra` (OpenTofu), `registrar`
├─ github/        the organization and its repos; `github-bootstrap`
├─ hetzner/       account and secrets (the host comes next)
├─ openrouter/    account, models, capped keys and card; `openrouter`, `orca-fleet`
├─ mercury/       the bank: CLI, account, one capped virtual card per vendor; `cards`
├─ public/        the brokerage: CLI, account; `brokerage`
├─ catalog/       what each pinned tool can do (_json/), and its extractors
├─ claude/        cloud session tools and network allowlist
├─ repo/          commit convention, lint
├─ tmux/ tools/ desktop/ welcome/ setup/   shared NixOS modules
└─ rpi5/ yoga-c940/                        devices: configs, images, checks
```

## One branch, release tags as channels

All work lands on **`main`**, through PRs. The channels are release tags that
only the pipeline moves:

- **`yoga-c940-beta`**: every push to `main` is checked, built, boot-tested and
  published as this **pre-release**.
- **`yoga-c940-stable`**: the same ISO, republished once **all** flake checks
  and the ISO boot test passed.

Stable download (always the last build that passed everything):

    https://github.com/kagamizo-dev/kagamizo/releases/download/yoga-c940-stable/yoga-c940-ephemeral.iso

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

Wallpaper: `modules/desktop/_assets/wallpaper/japan-countryside-4k.png` (drawn by `_assets/make-wallpaper.py`), set at startup by `swaybg`
(niri draws no wallpaper itself). To change it, replace that file (keep it a PNG under
~8 MB; the build checks) and push to `main`.

Hardware notes: Intel graphics only. The image carries only the firmware this
laptop needs (Intel AX201 Wi-Fi/Bluetooth, i915, Sound Open Firmware), which keeps
the ISO under GitHub's 2 GB release-asset limit. Expect the front speakers only;
the bottom pair needs an init sequence mainline Linux lacks.

## Raspberry Pi 5 SD card (paused)

Built from `main` as the `rpi5-beta` pre-release
(`rpi5-nixos-ephemeral.img.zip`; `rpi5-nixos-persistent.img.zip` is a fallback with a
normal writable card). Unzip with the Files app, then flash the `.img` with
EtchDroid. Same ephemeral idea: root in RAM, the card mounted read-only. Headless:
auto-login on the console straight into tmux.

## tmux and Proton Pass

Prefix is `Ctrl-a`. `prefix ?` opens a fuzzy-searchable list of every key binding;
`prefix Space` opens a grouped quick menu. Edit `modules/tmux/_nixos.nix`.

`pass-cli login` prints a URL to open on your phone. The CLI keeps its key in the
kernel keyring (RAM, cleared on reboot). It needs a Proton plan that includes the
CLI (Pass Plus/Family/Professional or a bundle). If keyring errors appear:
`PROTON_PASS_KEY_PROVIDER=fs pass-cli login` (fine here, since home is RAM).

## Cloudflare

The Cloudflare account is declared in Nix and applied by OpenTofu: PRs get a
read-only plan, merging applies it. Secrets live in Proton Pass and are named in
`secretspec.toml`. Setup and the token model:
[modules/cloudflare/README.md](modules/cloudflare/README.md).

## Identity: domains, mailboxes, vaults, accounts

Kagamizo's domains, their mailboxes, the Cloudflare and GitHub accounts and the
Proton Pass vaults are declared under `modules/` and type-checked with
nix-effects. The GitHub organization is applied by the `github-bootstrap`
workflow (`modules/github`).

## Money: one capped card per vendor

Nothing is paid with a long-lived card. Each vendor's module declares its own
Mercury virtual card with a spend limit (`mercury.cards.<vendor>`: OpenRouter's
is the sum of its key caps, Cloudflare's the registrar budget), and
`nix run .#cards -- plan|apply` issues, re-limits, freezes or cancels them.
Where Mercury reveals a card, its details go straight into a Proton Pass card
item. Moving money still asks for a tap in the Mercury app.

`nix run .#brokerage -- summary` reads Public (accounts, portfolio); any other
arguments go to Public's own CLI, with its secret from Proton Pass.

## Checks

`nix flake check` runs nixfmt, statix, deadnix, the identity and account type
checks, `tofu validate`, a niri config validation, a waybar config check, and VM tests (tmux key finder, niri desktop + welcome screen). CI also runs
actionlint and zizmor on the workflows, and the Yoga pipeline boots the finished
ISO under UEFI as a USB stick. Format locally with `nix fmt`.

Images contain no secrets: the repository is public.

## Changing things

There is no remote access by design. To change an image: merge to `main`, wait for
the pipeline, reflash. `yoga-c940-stable` follows by itself when everything passes. The base
only moves when you run `nix flake update`.
