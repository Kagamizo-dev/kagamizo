# Each governance agent as an Orca swarm: its own Proton Pass agent token
# (opening only its entity's sessions vault), its own Cedar principal, and an
# OpenCode config whose subagents are its agency-agents personas.
#
#   nix run .#orca-swarm -- <agent> [orca args]
#
# runs Orca as that agent: KAGAMIZO_PRINCIPAL=agent:<agent>, so every
# wrapper it calls (northwest, ...) is authorized as it, with the pass-cli
# session in ~/.pass-<agent>, signed in with its own token
# (PROTON_PASS_SWARM_<AGENT>_TOKEN in proton-agents, made by `proton apply`).
#
# Two layers, both from the same declarations: the Proton token decides which
# entity's sessions the swarm can read at all; Cedar decides which tools the
# wrappers will call for it. The principal is set by this launcher, so Cedar
# is the wrappers' check, not a boundary against code that skips them; the
# token's vault access is that boundary.
{
  lib,
  config,
  inputs,
  ...
}:
let
  top = config;
  cfg = config.governance;
  persona = p: "${inputs.agency-agents}/${p}.md";
  slug = p: lib.last (lib.splitString "/" p);
  tokenVar = name: "PROTON_PASS_SWARM_${lib.toUpper (lib.replaceStrings [ "-" ] [ "_" ] name)}_TOKEN";

  missing = lib.concatLists (
    lib.mapAttrsToList (
      name: a:
      map (p: "governance.agents.${name}: no persona ${p}") (
        lib.filter (p: !builtins.pathExists (persona p)) a.personas
      )
    ) cfg.agents
  );
in
{
  governance.problems = missing;

  proton.agents = lib.mapAttrs' (
    name: a:
    lib.nameValuePair "swarm-${name}" {
      vault = config.proton.infraVaults.agents;
      expiration = "1m";
      access = [
        {
          vault = config.proton.sessionVaults.${a.serves};
          role = "editor";
        }
      ];
      secret = tokenVar name;
    }
  ) cfg.agents;

  perSystem =
    { pkgs, config, ... }:
    let
      # A persona's body, without agency-agents' frontmatter.
      prompt =
        p:
        pkgs.runCommand "${slug p}.md" { } ''
          awk 'NR==1 && /^---$/ {fm=1; next} fm && /^---$/ {fm=0; next} !fm' ${persona p} > $out
        '';

      lead =
        name: a:
        let
          tools = lib.concatMapStrings (
            g:
            let
              provider = top.accounts.held.${g.account}.provider;
            in
            lib.concatStrings (
              lib.mapAttrsToList (
                tool: x:
                lib.optionalString (lib.elem x.effect g.effects) "- `${provider} --account ${g.account} ${
                  if x.command == null then "call ${tool}" else x.command
                }`: ${x.description}\n"
              ) (cfg.actions.${provider} or { })
            )
          ) a.grants;
        in
        pkgs.writeText "${name}.md" ''
          You lead the ${name} swarm: ${a.purpose}. You work for ${
            top.identity.checked.entities.${a.serves}.legalName
          } only.

          Delegate to your subagents (${
            lib.concatMapStringsSep ", " slug a.personas
          }) and bring their work together.

          What you can reach, through these commands and nothing else:
          ${if tools == "" then "- nothing yet: no account access is granted to this swarm.\n" else tools}
          You never pay, cancel, sign in, or change records: those stay with the
          entity's controller. Write what needs doing for them as a PR to the
          kagamizo repo, or as a note in your reply. A refusal from
          `governance` is final; do not look for another way round it.
        '';

      opencode =
        name: a:
        pkgs.writeText "opencode-${name}.json" (
          builtins.toJSON {
            "$schema" = "https://opencode.ai/config.json";
            model = "openrouter/${top.openrouter.defaultModel}";
            enabled_providers = [ "openrouter" ];
            provider.openrouter.models = lib.genAttrs top.openrouter.models (_: { });
            default_agent = name;
            agent = {
              ${name} = {
                description = a.purpose;
                mode = "primary";
                prompt = "{file:${lead name a}}";
              };
            }
            // lib.listToAttrs (
              map (
                p:
                lib.nameValuePair (slug p) {
                  description = "agency-agents ${p}";
                  mode = "subagent";
                  prompt = "{file:${prompt p}}";
                }
              ) a.personas
            );
            # The wrappers are the only commands that run unasked.
            permission.bash = {
              "*" = "ask";
            }
            // lib.genAttrs (map (g: "${top.accounts.held.${g.account}.provider} *") a.grants) (_: "allow");
          }
        );

      configs = pkgs.linkFarm "orca-swarms" (
        lib.mapAttrsToList (name: a: {
          name = "${name}.json";
          path = opencode name a;
        }) cfg.agents
      );
    in
    {
      packages.orca-swarms = configs;

      packages.orca-swarm = pkgs.writeShellApplication {
        name = "orca-swarm";
        runtimeInputs = [
          config.packages.secretspec
          config.packages.pass-cli
          config.packages.northwest
        ];
        text = ''
          agents=(${lib.concatStringsSep " " (lib.attrNames cfg.agents)})
          name=''${1:?usage: orca-swarm <''${agents[*]}> [orca args]}
          shift
          [ -f ${configs}/"$name".json ] || { echo "orca-swarm: no agent $name; declared: ''${agents[*]}" >&2; exit 2; }
          export PROTON_PASS_KEY_PROVIDER=''${PROTON_PASS_KEY_PROVIDER:-fs}
          export PROTON_PASS_SESSION_DIR=$HOME/.pass-$name
          pass-cli info >/dev/null 2>&1 || {
            echo "orca-swarm: sign $name's pass-cli in first, with its own token (proton-agents)" >&2
            exit 1
          }
          export KAGAMIZO_PRINCIPAL=agent:$name
          export OPENCODE_CONFIG=${configs}/$name.json
          exec secretspec run --file ${config.packages.secretspec-toml} --profile agent \
            --reason "orca swarm $name" -- orca "$@"
        '';
      };
    };
}
