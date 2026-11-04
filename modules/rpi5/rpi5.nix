# Raspberry Pi 5 SD card images on nvmd/nixos-raspberrypi: headless, console
# auto-login into tmux.
#
#   nix build .#image             ephemeral: RAM-only root (the default)
#   nix build .#image-persistent  a normal writable SD root, as a fallback
{ inputs, self, ... }:
let
  mkPi =
    extraModules:
    inputs.nixos-raspberrypi.lib.nixosSystem {
      specialArgs = inputs;
      modules = [
        (
          { nixos-raspberrypi, ... }:
          {
            imports = with nixos-raspberrypi.nixosModules; [
              sd-image
              raspberry-pi-5.base
            ];
          }
        )
        ./_nixos.nix
        self.nixosModules.tmux
      ]
      ++ extraModules;
    };
in
{
  flake = {
    nixosConfigurations = {
      rpi5 = mkPi [ ./_ephemeral.nix ];
      rpi5-persistent = mkPi [ ];
    };

    packages.aarch64-linux = {
      image = self.nixosConfigurations.rpi5.config.system.build.sdImage;
      image-persistent = self.nixosConfigurations.rpi5-persistent.config.system.build.sdImage;
    };
  };

  perSystem =
    { pkgs, ... }:
    {
      # Guards the amnesic layout: RAM root, read-only store source.
      checks.ephemeral-root =
        let
          fs = self.nixosConfigurations.rpi5.config.fileSystems;
        in
        assert fs."/".fsType == "tmpfs";
        assert builtins.elem "ro" fs."/nix/.ro-root".options;
        pkgs.runCommand "ephemeral-root-check" { } "touch $out";
    };
}
