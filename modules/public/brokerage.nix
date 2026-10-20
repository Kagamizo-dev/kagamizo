# `nix run .#brokerage -- <summary|public args...>`: Public's CLI under the
# secretspec profile `public`, so it mints its access tokens from the
# personal secret in Proton Pass and never asks for it.
#
#   brokerage summary        accounts, then the default account's portfolio
#   brokerage <public args>  anything else, e.g. `brokerage market quotes AAPL`
#
# Orders go through `public order preflight-single` before `order place`, as
# Public's CLI asks; nothing here places one by itself.
{
  lib,
  config,
  inputs,
  ...
}:
let
  top = config;
  cli = import ../_lib/cli.nix {
    inherit lib;
    fx = inputs.nix-effects.lib;
  };
in
{
  perSystem =
    { pkgs, config, ... }:
    let
      run = pkgs.writeShellApplication {
        name = "brokerage-run";
        runtimeInputs = [ config.packages.public ];
        text = ''
          : "''${PUBLIC_PERSONAL_SECRET:?}"
          case "''${1:-}" in
            summary)
              ${cli.public "accounts list" { }}
              ${cli.public "portfolio show" { }}
              ;;
            "")
              echo "usage: brokerage <summary|public args...>" >&2
              exit 2
              ;;
            *) exec public "$@" ;;
          esac
        '';
      };
    in
    {
      packages.brokerage = pkgs.writeShellApplication {
        name = "brokerage";
        runtimeInputs = [
          config.packages.secretspec
          config.packages.pass-cli
        ];
        text = builtins.seq top.accounts.checked ''
          export PROTON_PASS_KEY_PROVIDER=''${PROTON_PASS_KEY_PROVIDER:-fs}
          exec secretspec run --file ${config.packages.secretspec-toml} --profile public \
            --reason "brokerage $*" -- ${run}/bin/brokerage-run "$@"
        '';
      };
    };
}
