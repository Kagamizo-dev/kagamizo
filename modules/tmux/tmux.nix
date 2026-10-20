# tmux, on every image: Ctrl-a prefix, `prefix ?` key finder, a grouped quick
# menu. The VM test boots it and drives it like a user would.
{
  flake.nixosModules.tmux = ./_nixos.nix;

  perSystem =
    { pkgs, ... }:
    {
      checks.tmux = pkgs.testers.runNixOSTest ./_test.nix;
    };
}
