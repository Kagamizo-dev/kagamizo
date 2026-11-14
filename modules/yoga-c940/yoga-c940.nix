# Lenovo Yoga C940-14IIL live USB: a hybrid UEFI ISO with the niri desktop,
# root in RAM. The yoga-c940 workflow builds it, boots it under QEMU
# (_scripts/boot-iso.sh) and publishes it (_scripts/publish-release.sh).
#
#   nix build .#yoga-c940-iso  ->  result/iso/*.iso
{
  inputs,
  self,
  config,
  withSystem,
  ...
}:
{
  flake.nixosConfigurations.yoga-c940 = inputs.nixpkgs.lib.nixosSystem {
    modules = [
      ./_nixos.nix
      # The Kagamizo shell is the session (modules/shell).
      (withSystem "x86_64-linux" (
        { config, ... }:
        import ../shell/_nixos.nix {
          shell = config.packages.kagamizo-shell;
          target = "yoga-c940";
        }
      ))
      # The logistics CLI on the PATH (modules/logistics).
      (withSystem "x86_64-linux" (
        { config, ... }:
        {
          environment.systemPackages = [ config.packages.logistics ];
        }
      ))
      # Its runtimes: Windows and aarch64 programs (modules/shell).
      (config.shell.runtimeModule "yoga-c940")
      # Its reverse-engineering workbench (modules/rea).
      (config.rea.workbenchModule "yoga-c940")
      # Its scanners, for our own surfaces (modules/security).
      (config.security.toolsModule "yoga-c940")
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
