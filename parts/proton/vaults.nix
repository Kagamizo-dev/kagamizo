# Proton Pass as code. Vaults: one per entity (its logins) plus one per trust
# level for the infra secrets. Items: every secret reference in secretspec.toml
# names a vault and an item title.
#
#   proton plan     the diff: vaults and secret references, declared against
#                   what exists (titles only, never values)
#   proton apply    create the missing vaults
#
# Values are never written by this tool: they come from you (dashboard tokens)
# or from the bootstrap layer's outputs. Proton has no API for mail domains or
# addresses, so those stay manual: add the domain under Settings, Domain names,
# then copy the verification and DKIM values into identity.domains.<name>.proton.
{
  lib,
  config,
  inputs,
  ...
}:
let
  inherit (lib) mkOption types;
  t = import ../_lib/types.nix {
    inherit lib;
    fx = inputs.nix-effects.lib;
  };
  inherit (config.identity.checked) entities;
  cli = import ../_lib/cli.nix {
    inherit lib;
    fx = inputs.nix-effects.lib;
  };
  infraVaults = t.infraVaults entities config.proton.infraVaults;

  vaults = lib.unique (lib.mapAttrsToList (_: e: e.vault) entities ++ lib.attrValues infraVaults);

  # Every (vault, item) pair secretspec.toml refers to.
  inherit (config.proton.secretspec) providers profiles;
  vaultOf = provider: lib.removePrefix "protonpass://" providers.${provider};
  refs = lib.unique (
    lib.concatLists (
      lib.mapAttrsToList (
        _: profile:
        lib.mapAttrsToList (_: secret: {
          vault = vaultOf (lib.head profile.defaults.providers);
          inherit (secret.ref) item;
          required = secret.required or true;
        }) (removeAttrs profile [ "defaults" ])
      ) profiles
    )
  );
in
{
  options.proton = {
    infraVaults = mkOption {
      type = types.attrsOf types.str;
      description = "Vaults holding the infra secrets: root (person), entity, ci, agents.";
    };
    vaults = mkOption {
      type = types.listOf types.str;
      readOnly = true;
    };
  };

  config = {
    proton = {
      # Root-level secrets in your personal root vault; Kagamizo's own secrets
      # (its GitHub organization, its logins) in its vault. CI and agents each
      # get a vault of their own, so an agent token can never read the others.
      infraVaults = {
        root = "Zachariah-Root";
        entity = "Kagamizo-LLC";
        ci = "Kagamizo-CI";
        agents = "Kagamizo-Agents";
      };
      inherit vaults;
    };

    perSystem =
      { pkgs, config, ... }:
      {
        packages.proton = pkgs.writeShellApplication {
          name = "proton";
          runtimeInputs = [
            pkgs.jq
            config.packages.pass-cli
          ];
          text = ''
            usage="usage: proton <plan|apply>"
            declared=${lib.escapeShellArg (builtins.toJSON vaults)}
            refs=${lib.escapeShellArg (builtins.toJSON refs)}
            existing=$(${cli.passCli "vault list" { output = "json"; }} | jq -c '[.vaults[].name]')
            missing=$(jq -cn --argjson d "$declared" --argjson e "$existing" '$d - $e')

            case "''${1:?$usage}" in
              plan)
                echo "vaults:"
                jq -rn --argjson d "$declared" --argjson e "$existing" \
                  '$d[] | . as $v | if ($e | any(. == $v)) then "  ok        \($v)" else "+ create    \($v)" end'
                jq -rn --argjson d "$declared" --argjson e "$existing" \
                  '($e - $d)[] | "  unmanaged \(.) (left alone)"'

                echo "secret references (secretspec.toml):"
                jq -r '[.[].vault] | unique[]' <<<"$refs" | while read -r vault; do
                  if jq -e --arg v "$vault" 'any(. == $v)' <<<"$existing" >/dev/null; then
                    titles=$(${
                      cli.passCli "item list" {
                        vault-name.shell = "$vault";
                        output = "json";
                      }
                    } | jq -c '[.items[].title]')
                  else
                    titles='[]'
                  fi
                  jq -r --arg v "$vault" --argjson t "$titles" '.[] | select(.vault == $v) |
                    if (.item as $i | $t | any(. == $i)) then "  ok        \($v)/\(.item)"
                    elif .required then "- missing   \($v)/\(.item)"
                    else "  optional  \($v)/\(.item) (not set)" end' <<<"$refs"
                done
                ;;
              apply)
                jq -r '.[]' <<<"$missing" | while read -r name; do
                  ${cli.passCli "vault create" { name.shell = "$name"; }} >/dev/null
                  echo "created $name"
                done
                ;;
              *)
                echo "$usage" >&2
                exit 2
                ;;
            esac
          '';
        };
      };
  };
}
