# nix-images

NixOS SD card image for Raspberry Pi 5 (built on `nvmd/nixos-raspberrypi`).

1. Add your SSH public key in `modules/base.nix`.
2. Build (needs an aarch64 machine, or `boot.binfmt.emulatedSystems = [ "aarch64-linux" ]` on x86):

       nix build --accept-flake-config .#image

3. Flash: `zstd -d result/sd-image/*.img.zst -o rpi5.img` then write with `dd` or Raspberry Pi Imager.

Edit `modules/tmux.nix` for the tmux config. Update a running Pi with:

    nixos-rebuild switch --flake .#rpi5 --target-host pi@rpi5 --use-remote-sudo
