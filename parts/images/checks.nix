# Image guards and VM tests; `nix flake check` runs these (CI does the same).
{ self, ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      checks = {
        # Guards the amnesic layout: RAM root, read-only store source.
        ephemeral-root =
          let
            fs = self.nixosConfigurations.rpi5.config.fileSystems;
          in
          assert fs."/".fsType == "tmpfs";
          assert builtins.elem "ro" fs."/nix/.ro-root".options;
          pkgs.runCommand "ephemeral-root-check" { } "touch $out";
        niri-config = pkgs.runCommand "niri-config-check" { nativeBuildInputs = [ pkgs.niri ]; } ''
          niri validate --config ${../../modules/niri/config.kdl}
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
        disk-guard = pkgs.testers.runNixOSTest ../../tests/disk-guard.nix;
        # Boots a VM with the tmux module and drives it like a user would.
        tmux = pkgs.testers.runNixOSTest ../../tests/tmux.nix;
        desktop = pkgs.testers.runNixOSTest ../../tests/desktop.nix;
      };
    };
}
