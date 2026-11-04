# Lenovo Yoga C940-14IIL live USB: a hybrid UEFI ISO with the niri desktop,
# root in RAM. The yoga-c940 workflow builds it, boots it under QEMU
# (_scripts/boot-iso.sh) and publishes it (_scripts/publish-release.sh).
#
#   nix build .#yoga-c940-iso  ->  result/iso/*.iso
{ inputs, self, ... }:
{
  flake.nixosConfigurations.yoga-c940 = inputs.nixpkgs.lib.nixosSystem {
    modules = [
      ./_nixos.nix
    ]
    ++ (with self.nixosModules; [
      tools
      tmux
      desktop
      welcome
      setup
    ]);
  };

  perSystem.packages.yoga-c940-iso = self.nixosConfigurations.yoga-c940.config.system.build.isoImage;
}
