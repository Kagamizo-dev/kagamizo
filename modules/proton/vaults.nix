# Proton Pass as code. Vaults: one per entity (its logins) plus one per trust
# level for the infra secrets. Items: every secret reference in secretspec.toml
# names a vault and an item title.
#
#   proton plan     the diff: vaults, agents and secret references, declared
#                   against what exists (titles only, never values)
#   proton apply    create the missing vaults and agents (agents.nix), store
#                   each new agent token in your root vault, grant the access
#
# Values are never written by this tool: they come from you (dashboard tokens)
# or from `bootstrap`. Proton has no API for mail domains or
# addresses, so those stay manual: add the domain under Settings, Domain names,
# then copy the verification and DKIM values into identity.domains.<name>.proton.
{
  lib,
  config,
  inputs,
  ...
}:
let
  top = config;
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
          vault = vaultOf (lib.head (secret.providers or profile.defaults.providers));
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
      description = "Vaults holding the infra secrets: root (person), entity, ci, agents, state, host.";
    };
    vaults = mkOption {
      type = types.listOf types.str;
      readOnly = true;
    };
  };

  config = {
    proton = {
      # Your personal root vault (your own logins, the agent tokens until they
      # are handed over); Kagamizo's own secrets (its GitHub organization, its
      # logins) in its vault. CI and agents each get a vault of their own, so an
      # agent token can never read the others; the OpenTofu state sits in a
      # vault both open, at the roles in agents.nix.
      infraVaults = {
        root = "Zachariah-Root";
        entity = "Kagamizo-LLC";
        ci = "Kagamizo-CI";
        agents = "Kagamizo-Agents";
        state = "Kagamizo-State";
        # What the always-on host (modules/kagamizo-host) reads at boot.
        host = "Kagamizo-Host";
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
            config.packages.secretspec
          ];
          # Builds only while the declared plans cover what the repo needs.
          text = builtins.seq top.accounts.checked ''
            usage="usage: proton <plan|apply>"
            declared=${lib.escapeShellArg (builtins.toJSON vaults)}
            refs=${lib.escapeShellArg (builtins.toJSON refs)}
            existing=$(${cli.passCli "vault list" { output = "json"; }} | jq -c '[.vaults[].name]')
            missing=$(jq -cn --argjson d "$declared" --argjson e "$existing" '$d - $e')
            agents=${lib.escapeShellArg (builtins.toJSON top.proton.agents)}
            spec=${config.packages.secretspec-toml}
            # Names of the agents that exist, whatever the listing's nesting.
            liveAgents() {
              ${cli.passCli "agent list" { output = "json"; }} |
                jq -c --argjson a "$agents" '[.. | objects | .name? // empty | strings | select(. as $n | $a | has($n))] | unique'
            }

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

                echo "agents (agents.nix):"
                jq -rn --argjson a "$agents" --argjson l "$(liveAgents)" '$a | to_entries[] |
                  "\(if (.key as $k | $l | index($k)) then "  ok      " else "+ create  " end)  \(.key): \(.value.vault)\([.value.access[] | ", \(.vault) as \(.role)"] | add // "") (\(.value.expiration))"'
                ;;
              apply)
                jq -r '.[]' <<<"$missing" | while read -r name; do
                  ${cli.passCli "vault create" { name.shell = "$name"; }} >/dev/null
                  echo "created $name"
                done

                live=$(liveAgents)
                for name in $(jq -r 'keys[]' <<<"$agents"); do
                  if ! jq -e --arg n "$name" 'index($n)' <<<"$live" >/dev/null; then
                    out=$(${
                      cli.passCli "agent create" {
                        name.shell = "$name";
                        vault.shell = "$(jq -r --arg n \"$name\" '.[$n].vault' <<<\"$agents\")";
                        expiration.shell = "$(jq -r --arg n \"$name\" '.[$n].expiration' <<<\"$agents\")";
                      }
                    })
                    token=$(grep -o 'pst_[^[:space:]"]*' <<<"$out" | head -1 || true)
                    unset out
                    if [ -z "$token" ]; then
                      ${cli.passCli "agent delete" { name.shell = "$name"; }} >/dev/null
                      echo "agent $name: no token in pass-cli's output; deleted it again" >&2
                      exit 1
                    fi
                    # A token that cannot be stored is useless: delete the agent.
                    if ! printf %s "$token" | secretspec set "$(jq -r --arg n "$name" '.[$n].secret' <<<"$agents")" \
                      --file "$spec" --profile proton-agents --from-file - \
                      --reason "proton apply: store the token of new agent $name" >/dev/null; then
                      ${cli.passCli "agent delete" { name.shell = "$name"; }} >/dev/null
                      echo "agent $name: could not store its token; deleted it again" >&2
                      exit 1
                    fi
                    unset token
                    echo "created agent $name (token stored in ${top.proton.infraVaults.root})"
                    # Granted once, with the agent: pass-cli cannot list an
                    # agent's access, and Proton refuses a repeated grant
                    # (NotAllowed). Changing an existing agent's access means
                    # deleting it and applying again, which mints a new token.
                    jq -c --arg n "$name" '.[$n].access[]' <<<"$agents" | while read -r grant; do
                      ${
                        cli.passCli "agent access grant" {
                          name.shell = "$name";
                          vault-name.shell = "$(jq -r .vault <<<\"$grant\")";
                          role.shell = "$(jq -r .role <<<\"$grant\")";
                        }
                      } >/dev/null
                      echo "agent $name: $(jq -r '"\(.vault) as \(.role)"' <<<"$grant")"
                    done
                  fi
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
