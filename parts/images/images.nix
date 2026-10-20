# The bootable images: Raspberry Pi 5 SD cards and the Yoga C940 live USB.
# Each device is a directory under ../../devices that pulls in the shared
# ../../profiles it wants.
{ inputs, self, ... }:
let
  inherit (inputs) nixos-raspberrypi;

  mkPi =
    extraModules:
    nixos-raspberrypi.lib.nixosSystem {
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
        ../../devices/rpi5/default.nix
        ../../profiles/tmux.nix
      ]
      ++ extraModules;
    };
in
{
  flake = {
    nixosConfigurations = {
      # Default: amnesic, RAM-only root.
      rpi5 = mkPi [ ../../devices/rpi5/ephemeral.nix ];
      # Fallback with a normal writable SD root, in case the ephemeral
      # layout misbehaves on real hardware.
      rpi5-persistent = mkPi [ ];
      # Lenovo Yoga C940 live USB (x86_64), same nixpkgs as the Pi images.
      yoga-c940 = inputs.nixpkgs.lib.nixosSystem {
        modules = [ ../../devices/yoga-c940 ];
      };
    };

    # nix build .#image  ->  result/sd-image/*.img.zst
    packages.aarch64-linux = {
      image = self.nixosConfigurations.rpi5.config.system.build.sdImage;
      image-persistent = self.nixosConfigurations.rpi5-persistent.config.system.build.sdImage;
    };
  };

  # nix build .#yoga-c940-iso  ->  result/iso/*.iso
  perSystem.packages.yoga-c940-iso = self.nixosConfigurations.yoga-c940.config.system.build.isoImage;
}
