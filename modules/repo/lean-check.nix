# Lean proof checks with no shell: `config.kagamizo.leanCheck` makes a
# derivation whose builder is the lean-check Rust binary (./_lean-check),
# which joins a module's Lean source with the facts it renders, runs Lean,
# and creates $out only when every theorem holds. New checks use it, and
# the shell-built ones move to it as their language exceptions close
# (./languages.nix).
#
#   config.kagamizo.leanCheck { name; source; facts; }
{ lib, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      lean-check = pkgs.rustPlatform.buildRustPackage {
        pname = "lean-check";
        version = "0.1.0";
        src = ./_lean-check;
        cargoLock.lockFile = ./_lean-check/Cargo.lock;
        meta.mainProgram = "lean-check";
      };
    in
    {
      options.kagamizo.leanCheck = lib.mkOption {
        type = lib.types.functionTo lib.types.package;
        readOnly = true;
        description = "Make a Lean proof check from { name; source; facts; }, built by lean-check.";
      };

      config = {
        packages.lean-check = lean-check;
        kagamizo.leanCheck =
          {
            name,
            source,
            facts,
          }:
          derivation {
            inherit name facts;
            inherit (pkgs.stdenv.hostPlatform) system;
            builder = lib.getExe lean-check;
            args = [
              (lib.getExe' pkgs.lean4 "lean")
              source
            ];
            passAsFile = [ "facts" ];
          };
      };
    };
}
