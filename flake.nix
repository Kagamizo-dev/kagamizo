{
  description = "Custom NixOS SD card image for Raspberry Pi 5";

  inputs.nixos-raspberrypi.url = "github:nvmd/nixos-raspberrypi/main";

  # Prebuilt kernel/firmware; avoids compiling the Pi kernel yourself.
  # Build with: nix build --accept-flake-config .#image
  nixConfig = {
    extra-substituters = [ "https://nixos-raspberrypi.cachix.org" ];
    extra-trusted-public-keys = [
      "nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI="
    ];
  };

  outputs = { self, nixos-raspberrypi, ... }@inputs: {
    nixosConfigurations.rpi5 = nixos-raspberrypi.lib.nixosSystem {
      specialArgs = inputs;
      modules = [
        ({ nixos-raspberrypi, ... }: {
          imports = with nixos-raspberrypi.nixosModules; [
            sd-image
            raspberry-pi-5.base
          ];
        })
        ./modules/base.nix
        ./modules/tmux.nix
      ];
    };

    # nix build .#image  ->  result/sd-image/*.img.zst
    packages.aarch64-linux.image = self.nixosConfigurations.rpi5.config.system.build.sdImage;
    packages.x86_64-linux.image = self.nixosConfigurations.rpi5.config.system.build.sdImage;
  };
}
