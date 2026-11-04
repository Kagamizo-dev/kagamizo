# Signing up for anything with a web form, the one step most providers offer
# no API for. Everything around it is code:
#
#   signup plan             every planned account with a signup: what it
#                           claims, with which address, its recorded findings,
#                           and whether its vault item exists yet
#   signup prepare <name>   create the login item in the owner's vault (email,
#                           URL, handle; a generated password when the account
#                           has its own login), so the form is filled from
#                           Proton Pass and the 2FA seed is saved back there.
#                           An active account with a signup is one held from
#                           before: its item is the login it is moved to.
#
# After the form: set the account's status to "active" in held.nix, and from
# then on the provider's CLI or API takes over.
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
  inherit (config.identity.checked) entities;
  pending = lib.mapAttrs (
    _: a:
    a.signup
    // {
      inherit (a)
        provider
        plan
        owner
        status
        ;
      vault = entities.${a.owner}.vault;
    }
  ) (lib.filterAttrs (_: a: a.signup != null) config.accounts.held);
in
{
  perSystem =
    { pkgs, config, ... }:
    {
      packages.signup = pkgs.writeShellApplication {
        name = "signup";
        runtimeInputs = [
          pkgs.jq
          config.packages.pass-cli
        ];
        # Builds only while the declared plans cover what the repo needs.
        text = builtins.seq top.accounts.checked ''
          usage="usage: signup plan | prepare <name>"
          export PROTON_PASS_KEY_PROVIDER=''${PROTON_PASS_KEY_PROVIDER:-fs}
          pending=${lib.escapeShellArg (builtins.toJSON pending)}

          exists() { # vault title
            ${
              cli.passCli "item list" {
                vault-name.shell = "$1";
                output = "json";
              }
            } | jq -e --arg t "$2" 'any(.items[]; .title == $t)' >/dev/null
          }

          cmd=''${1:?$usage}
          shift
          case "$cmd" in
            plan)
              for name in $(jq -r 'to_entries[] | select(.value.status == "planned") | .key' <<<"$pending"); do
                a=$(jq -c --arg n "$name" '.[$n]' <<<"$pending")
                vault=$(jq -r .vault <<<"$a")
                if exists "$vault" "$name"; then item="ready in $vault"; else item="+ prepare in $vault"; fi
                # shellcheck disable=SC2016 # jq variables, not shell ones
                jq -r --arg n "$name" --arg i "$item" '
                  "\($n): \(.provider) \(.plan), claim \(.handle) with \(.email)",
                  "  form:   \(.url)",
                  "  login:  \(if .credential == "parent" then "from \(.parent)" else "own password, 2FA seed saved to the item" end)",
                  "  item:   \($i)",
                  (.findings[] | "  found:  \(.fact) (\(.source), \(.checked))")' <<<"$a"
              done
              ;;
            prepare)
              name=''${1:?$usage}
              a=$(jq -c --arg n "$name" '.[$n] // empty' <<<"$pending")
              [ -n "$a" ] || { echo "no planned account $name with a signup" >&2; exit 1; }
              vault=$(jq -r .vault <<<"$a")
              if exists "$vault" "$name"; then
                echo "$vault/$name exists already"
                exit 0
              fi
              if [ "$(jq -r .credential <<<"$a")" = password ]; then
                ${
                  cli.passCli "item create login" {
                    vault-name.shell = "$vault";
                    title.shell = "$name";
                    email.shell = "$(jq -r .email <<<\"$a\")";
                    username.shell = "$(jq -r .handle <<<\"$a\")";
                    url.shell = "$(jq -r .url <<<\"$a\")";
                    generate-password = true;
                  }
                } >/dev/null
              else
                ${
                  cli.passCli "item create login" {
                    vault-name.shell = "$vault";
                    title.shell = "$name";
                    email.shell = "$(jq -r .email <<<\"$a\")";
                    username.shell = "$(jq -r .handle <<<\"$a\")";
                    url.shell = "$(jq -r .url <<<\"$a\")";
                  }
                } >/dev/null
              fi
              echo "prepared $vault/$name"
              ;;
            *)
              echo "$usage" >&2
              exit 2
              ;;
          esac
        '';
      };
    };
}
