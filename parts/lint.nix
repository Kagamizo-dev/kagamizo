# Formatting and lint over every Nix file in the repo.
{ self, ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      checks = {
        formatting = pkgs.runCommand "nixfmt-check" { nativeBuildInputs = [ pkgs.nixfmt ]; } ''
          find ${self} -name '*.nix' -print0 | xargs -0 nixfmt --check
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
      };
    };
}
