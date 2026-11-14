# The niri desktop: compositor config, waybar, wallpaper. Its assets are
# checked here because the desktop only finds out about them at runtime.
{
  flake.nixosModules.desktop = ./_nixos.nix;

  perSystem =
    { pkgs, ... }:
    {
      checks = {
        niri-config = pkgs.runCommand "niri-config-check" { nativeBuildInputs = [ pkgs.niri ]; } ''
          niri validate --config ${./_assets/niri/config.kdl}
          touch $out
        '';
        # The top bar config must be valid JSON (waybar only finds out at runtime).
        waybar-config = pkgs.runCommand "waybar-config-check" { nativeBuildInputs = [ pkgs.jq ]; } ''
          jq -e . ${./_assets/waybar/config.json} > /dev/null
          touch $out
        '';
        # The wallpaper must be a real PNG and small enough not to threaten the ISO size.
        wallpaper = pkgs.runCommand "wallpaper-check" { nativeBuildInputs = [ pkgs.file ]; } ''
          f=${./_assets/wallpaper/japan-countryside-4k.png}
          file "$f" | grep -q "PNG image data"
          test "$(stat -c %s "$f")" -lt 8000000
          touch $out
        '';
        desktop = pkgs.testers.runNixOSTest ./_test.nix;
      };
    };
}
