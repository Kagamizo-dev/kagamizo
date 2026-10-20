# Proton Pass vaults: one per entity (its logins) plus one per trust level for
# the infra secrets. `proton` reconciles the account with this list through
# pass-cli; it creates missing vaults and never deletes or renames one.
#
#   proton plan     what exists, what is missing
#   proton apply    create the missing vaults
#
# Proton has no API for mail domains or addresses, so those stay manual: add
# the domain under Settings, Domain names, then copy the verification and DKIM
# values into identity.domains.<name>.proton.
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
  infraVaults = t.infraVaults config.proton.infraVaults;

  vaults = lib.unique (
    lib.mapAttrsToList (_: e: e.vault) config.identity.checked.entities ++ lib.attrValues infraVaults
  );
in
{
  options.proton = {
    infraVaults = mkOption {
      type = types.attrsOf types.str;
      description = "Vaults holding the infra secrets: root (you), ci, agents.";
    };
    vaults = mkOption {
      type = types.listOf types.str;
      readOnly = true;
    };
  };

  config = {
    proton = {
      # Root is the Kagamizo vault: only you ever log in to it. CI and agents
      # each get a vault of their own, so an agent token can never read the
      # root token.
      infraVaults = {
        root = "Kagamizo-LLC";
        ci = "Kagamizo-CI";
        agents = "Kagamizo-Agents";
      };
      inherit vaults;
    };

    perSystem =
      { pkgs, ... }:
      {
        packages.proton = pkgs.writeShellApplication {
          name = "proton";
          runtimeInputs = [ pkgs.jq ];
          text = ''
            usage="usage: proton <plan|apply>"
            declared=${lib.escapeShellArg (builtins.toJSON vaults)}
            existing=$(pass-cli vault list --output json | jq -c '[.vaults[].name]')
            missing=$(jq -cn --argjson d "$declared" --argjson e "$existing" '$d - $e')

            case "''${1:?$usage}" in
              plan)
                jq -rn --argjson d "$declared" --argjson e "$existing" \
                  '$d[] | . as $v | if ($e | any(. == $v)) then "  ok        \($v)" else "+ create    \($v)" end'
                jq -rn --argjson d "$declared" --argjson e "$existing" \
                  '($e - $d)[] | "  unmanaged \(.) (left alone)"'
                ;;
              apply)
                jq -r '.[]' <<<"$missing" | while read -r name; do
                  pass-cli vault create --name "$name" >/dev/null
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
