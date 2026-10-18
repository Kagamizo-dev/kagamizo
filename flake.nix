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
      infra = import ./infra { inherit pkgs; };
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
        }
        // {
          # Lenovo Yoga C940 live USB (x86_64), same nixpkgs as the Pi images.
          yoga = nixos-raspberrypi.inputs.nixpkgs.lib.nixosSystem {
            modules = [ ./hosts/yoga-c940.nix ];
          };
        };

      # nix build .#image  ->  result/sd-image/*.img.zst
      packages.aarch64-linux = {
        image = self.nixosConfigurations.rpi5.config.system.build.sdImage;
        image-persistent = self.nixosConfigurations.rpi5-persistent.config.system.build.sdImage;
      };

      # nix build .#yoga-iso  ->  result/iso/*.iso
      packages.x86_64-linux = {
        yoga-iso = self.nixosConfigurations.yoga.config.system.build.isoImage;
        # nix run .#infra -- cloudflare plan  (see infra/README.md)
        infra = infra.app;
      };

      formatter.x86_64-linux = pkgs.nixfmt;

      # `nix flake check` runs these (CI does the same).
      checks.x86_64-linux = {
        formatting = pkgs.runCommand "nixfmt-check" { nativeBuildInputs = [ pkgs.nixfmt ]; } ''
          nixfmt --check ${self}/flake.nix ${self}/hosts/*.nix ${self}/modules/*.nix ${self}/tests/*.nix ${self}/infra/*.nix
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
        niri-config = pkgs.runCommand "niri-config-check" { nativeBuildInputs = [ pkgs.niri ]; } ''
          niri validate --config ${./modules/niri/config.kdl}
          touch $out
        '';
        # The Yoga image must carry the internal-disk guard.
        yoga-disk-guard =
          let
            cfg = self.nixosConfigurations.yoga.config;
          in
          assert cfg.systemd.services ? internal-disk-guard;
          assert pkgs.lib.hasInfix "--setro" cfg.services.udev.extraRules;
          pkgs.runCommand "yoga-disk-guard-check" { } "touch $out";
        # Both infra layers against the pinned Cloudflare provider schema.
        infra = infra.check;
        disk-guard = pkgs.testers.runNixOSTest ./tests/disk-guard.nix;
        # Boots a VM with the tmux module and drives it like a user would.
        tmux = pkgs.testers.runNixOSTest ./tests/tmux.nix;
        desktop = pkgs.testers.runNixOSTest ./tests/desktop.nix;
      };
    };
}
