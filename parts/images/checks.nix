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
          niri validate --config ${../../profiles/niri/config.kdl}
          touch $out
        '';
        # The top bar config must be valid JSON (waybar only finds out at runtime).
        waybar-config = pkgs.runCommand "waybar-config-check" { nativeBuildInputs = [ pkgs.jq ]; } ''
          jq -e . ${../../profiles/waybar/config.json} > /dev/null
          touch $out
        '';
        # The wallpaper must be a real PNG and small enough not to threaten the ISO size.
        wallpaper = pkgs.runCommand "wallpaper-check" { nativeBuildInputs = [ pkgs.file ]; } ''
          f=${../../profiles/wallpaper/japan-countryside-4k.png}
          file "$f" | grep -q "PNG image data"
          test "$(stat -c %s "$f")" -lt 8000000
          touch $out
        '';
        # Boots a VM with the tmux module and drives it like a user would.
        tmux = pkgs.testers.runNixOSTest ../../tests/tmux.nix;
        desktop = pkgs.testers.runNixOSTest ../../tests/desktop.nix;
      };
    };
}
