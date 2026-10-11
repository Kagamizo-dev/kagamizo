{
  description = "Custom NixOS SD card image for Raspberry Pi 5";

  # Pinned by flake.lock. Upstream follows the stable nixos-26.05 channel, so
  # the base only moves when `nix flake update` is run on purpose.
  inputs.nixos-raspberrypi.url = "git+https://github.com/nvmd/nixos-raspberrypi?ref=main";

  # Prebuilt kernel/firmware; avoids compiling the Pi kernel yourself.
  nixConfig = {
    extra-substituters = [ "https://nixos-raspberrypi.cachix.org" ];
    extra-trusted-public-keys = [
      "nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI="
    ];
  };

  outputs =
    { self, nixos-raspberrypi, ... }@inputs:
    let
      # Same nixpkgs the image is built from.
      pkgs = import nixos-raspberrypi.inputs.nixpkgs { system = "x86_64-linux"; };
    in
    {
      nixosConfigurations =
        let
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
                ./modules/base.nix
                ./modules/tmux.nix
              ]
              ++ extraModules;
            };
        in
        {
          # Default: amnesic, RAM-only root.
          rpi5 = mkPi [ ./modules/ephemeral.nix ];
          # Fallback with a normal writable SD root, in case the ephemeral
          # layout misbehaves on real hardware.
          rpi5-persistent = mkPi [ ];
        };

      # nix build .#image  ->  result/sd-image/*.img.zst
      packages.aarch64-linux = {
        image = self.nixosConfigurations.rpi5.config.system.build.sdImage;
        image-persistent = self.nixosConfigurations.rpi5-persistent.config.system.build.sdImage;
      };

      formatter.x86_64-linux = pkgs.nixfmt;

      # `nix flake check` runs these (CI does the same).
      checks.x86_64-linux = {
        formatting = pkgs.runCommand "nixfmt-check" { nativeBuildInputs = [ pkgs.nixfmt ]; } ''
          nixfmt --check ${self}/flake.nix ${self}/modules/*.nix ${self}/tests/*.nix
          touch $out
        '';
        statix = pkgs.runCommand "statix-check" { nativeBuildInputs = [ pkgs.statix ]; } ''
          statix check ${self}
          touch $out
        '';
        deadnix = pkgs.runCommand "deadnix-check" { nativeBuildInputs = [ pkgs.deadnix ]; } ''
          deadnix --fail ${self}
          touch $out
        '';
        # Guards the amnesic layout: RAM root, read-only store source.
        ephemeral-root =
          let
            fs = self.nixosConfigurations.rpi5.config.fileSystems;
          in
          assert fs."/".fsType == "tmpfs";
          assert builtins.elem "ro" fs."/nix/.ro-root".options;
          pkgs.runCommand "ephemeral-root-check" { } "touch $out";
        # Boots a VM with the tmux module and drives it like a user would.
        tmux = pkgs.testers.runNixOSTest ./tests/tmux.nix;
      };
    };
}
