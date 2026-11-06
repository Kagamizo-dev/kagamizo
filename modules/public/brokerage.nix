# `nix run .#brokerage -- <summary|public args...>`: Public's CLI under the
# secretspec profile `public`, so it mints its access tokens from the
# personal secret in Proton Pass and never asks for it.
#
#   brokerage summary        accounts, then the default account's portfolio
#   brokerage <public args>  anything else, e.g. `brokerage market quotes AAPL`
#                            or `brokerage --json portfolio show` (the CLI's
#                            global options go before the command)
#
# Every command line is checked against Public's pinned CLI (its Lean model,
# modules/lean) by `api-check` before governance or Public sees it: an
# unknown command, option or value type is refused here. ./_lean/Calls.lean
# proves the calls the wrappers make are accepted and others refused.
# The command's words (after any global options) name the governance action
# `public:<words>`; a command whose endpoints the personal secret is not
# known to call (./authorization.nix) is refused before governance is asked.
# When PUBLIC_ACCOUNT_ID is set (Mirazo-Root/public-account-id, the one
# BROKERAGE account), every command that takes --account-id gets it, unless
# the command line names one.
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
  catalog = lib.importJSON ../catalog/_json/public.json;
  id = lib.replaceStrings [ " " ] [ "-" ];
  # The CLI's global options, by whether they take a value, so the wrapper
  # steps over them to the command's words.
  globalFlags = lib.attrNames (lib.filterAttrs (_: o: o.type == "boolean") catalog.global);
  globalValued = lib.attrNames (lib.filterAttrs (_: o: o.type != "boolean") catalog.global);
  # Each would send the stored secret elsewhere or bypass it.
  refused = [
    "base-url"
    "token"
  ];
  takesAccount = lib.attrNames (lib.filterAttrs (_: c: c.options ? account-id) catalog.commands);
in
{
  perSystem =
    { pkgs, config, ... }:
    let
      commandsJson = pkgs.writeText "public-commands.json" (
        builtins.toJSON (lib.mapAttrs (c: _: id c) catalog.commands)
      );
      blockedJson = pkgs.writeText "public-blocked.json" (builtins.toJSON top.public.blocked);
      run = pkgs.writeShellApplication {
        name = "brokerage-run";
        runtimeInputs = [ config.packages.public ];
        text = ''
          : "''${PUBLIC_PERSONAL_SECRET:?}"
          case "''${1:-}" in
            summary)
              ${cli.public "accounts list" { }}
              if [ -n "''${PUBLIC_ACCOUNT_ID:-}" ]; then
                ${cli.public "portfolio show" { account-id.shell = "$PUBLIC_ACCOUNT_ID"; }}
              else
                ${cli.public "portfolio show" { }}
              fi
              ;;
            "")
              echo "usage: brokerage <summary|public args...>" >&2
              exit 2
              ;;
            *)
              # The brokerage account, for a command that takes one and was
              # not given one (BROKERAGE_COMMAND is set by brokerage).
              takes=${lib.escapeShellArg " ${lib.concatStringsSep " " takesAccount} "}
              if [[ "$takes" == *" ''${BROKERAGE_COMMAND:-} "* ]] && [ -n "''${PUBLIC_ACCOUNT_ID:-}" ]; then
                given=
                for arg in "$@"; do
                  case "$arg" in --account-id | --account-id=* | -a) given=1 ;; esac
                done
                [ -n "$given" ] || set -- "$@" --account-id "$PUBLIC_ACCOUNT_ID"
              fi
              exec public "$@"
              ;;
          esac
        '';
      };
    in
    {
      checks.public-calls = pkgs.runCommand "public-calls" { nativeBuildInputs = [ pkgs.lean4 ]; } ''
        cat ${config.packages.lean-api-core} ${config.packages.lean-api-public} ${./_lean/Calls.lean} > Check.lean
        lean Check.lean
        touch $out
      '';
      packages.brokerage = pkgs.writeShellApplication {
        name = "brokerage";
        runtimeInputs = [
          config.packages.secretspec
          config.packages.pass-cli
          config.packages.governance-authorize
          config.packages.api-check
          pkgs.jq
        ];
        text = builtins.seq top.accounts.checked ''
          export PROTON_PASS_KEY_PROVIDER=''${PROTON_PASS_KEY_PROVIDER:-fs}
          if [ "''${1:-}" != summary ]; then
            api-check ${config.packages.api-model-public} "$@"
          fi
          for arg in "$@"; do
            case "$arg" in
              ${lib.concatMapStringsSep " | " (o: "--${o} | --${o}=*") refused})
                echo "brokerage: $arg is refused: it would bypass the stored secret or send it elsewhere" >&2
                exit 2 ;;
            esac
          done
          # The command's words: after the CLI's global options, up to the
          # command's first option.
          words=()
          skip=
          for arg in "$@"; do
            if [ -n "$skip" ]; then skip=; continue; fi
            case "$arg" in
              ${lib.concatMapStringsSep " | " (o: "--${o} | --no-${o}") globalFlags}) continue ;;
              ${lib.concatMapStringsSep " | " (o: "--${o}=*") globalValued}) continue ;;
              ${lib.concatMapStringsSep " | " (o: "--${o}") globalValued}) skip=1; continue ;;
              -*) break ;;
            esac
            words+=("$arg")
          done
          if [ "''${words[0]:-}" = summary ]; then
            action=summary
            command=summary
          else
            # The longest run of leading words that is a command of the pinned CLI.
            action=
            for ((n = ''${#words[@]}; n > 0; n--)); do
              action=$(jq -r --arg c "''${words[*]:0:n}" '.[$c] // empty' ${commandsJson})
              [ -z "$action" ] || { command=''${words[*]:0:n}; break; }
            done
            [ -n "$action" ] || { echo "brokerage: no command of Public's CLI in: $*" >&2; exit 2; }
            # Never a call the personal secret is not known to make
            # (./authorization.nix).
            why=$(jq -r --arg c "$command" '.[$c] // empty' ${blockedJson})
            if [ -n "$why" ]; then
              echo "brokerage: $command is refused: $why" >&2
              exit 3
            fi
          fi
          governance-authorize "public:$action" public-mirazo
          export BROKERAGE_COMMAND=$command
          exec secretspec run --file ${config.packages.secretspec-toml} --profile "''${PUBLIC_PROFILE:-public}" \
            --reason "brokerage $*" -- ${run}/bin/brokerage-run "$@"
        '';
      };
    };
}
