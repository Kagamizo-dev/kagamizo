# Cloudflare as code: each layer is plain Nix rendered to OpenTofu's JSON
# syntax, run by the `infra` app with secrets supplied by secretspec.
#
#   nix run .#infra -- <ci|agent> <tofu args...>
#
# The first word is the secretspec profile, i.e. the view: `agent` reads (PR
# plans), `ci` applies. The state is a local file fetched from the state vault
# (TOFU_STATE) and, under `ci`, written back when the run changed it, so Proton
# Pass holds it like every other secret. Tokens come first, from `bootstrap`.
{
  config,
  lib,
  inputs,
  ...
}:
let
  top = config;
  inherit (config.identity.checked) domains;
  statusOn = config.accounts.held.cloudflare.products ? zeroTrust;
  cli = import ../_lib/cli.nix {
    inherit lib;
    fx = inputs.nix-effects.lib;
  };
in
{
  # The layer's state, in the state vault every reader shares (proton.agents
  # gives ci editor, agents viewer).
  statestore.backends.cloudflare.vault = top.proton.infraVaults.state;

  perSystem =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    let
      tofu = pkgs.opentofu.withPlugins (p: [ p.cloudflare_cloudflare ]);

      # State stays local to the run; `infra` moves it in and out of Proton
      # Pass. Encrypted with TOFU_STATE_PASSPHRASE before it leaves tofu.
      terraform = {
        required_providers.cloudflare = {
          source = "cloudflare/cloudflare";
          version = "~> 5.19";
        };
        # Served by statestore-run (../statestore) from Proton Pass.
        backend.http = { };
      };

      # Each layer is checked against the pinned provider (catalog/) before it
      # is written out.
      configs = lib.mapAttrs (name: c: pkgs.writeText "${name}.tf.json" (builtins.toJSON (cli.tofu c))) {
        cloudflare =
          lib.foldl' lib.recursiveUpdate (import ./_zones.nix { inherit lib domains terraform; })
            [
              # status.mirazo.org is served only behind Access: the whole
              # layer waits for the owner to turn Zero Trust on
              # (accounts.held.cloudflare.products.zeroTrust).
              (lib.optionalAttrs statusOn (
                import ./_status.nix {
                  inherit (top.cloudflare.checked) accountId;
                  zoneId = domains."mirazo.org".zoneId;
                  hostname = "status.mirazo.org";
                  viewers = [ "zach@mirazo.org" ];
                  html = config.site.statusHtml;
                  repoFullName = "${top.github.org}/kagamizo";
                }
              ))
              # jingzo-host's agents, through their tunnel behind Access
              # (../hetzner/agents.nix).  Agent team service tokens and
              # policies (./_agents-access.nix) attach agent-svc tokens to
              # the applications the agents' tools justify.
              (lib.optionalAttrs statusOn (
                let
                  agentsAccess = import ./_agents-access.nix {
                    inherit lib;
                    inherit (top.cloudflare.checked) accountId;
                    agents = top.governance.agents;
                  };
                  inherit (agentsAccess) agentPolicyRefs;
                in
                lib.recursiveUpdate (import ./_agents.nix {
                  inherit lib;
                  inherit (top.cloudflare.checked) accountId;
                  inherit (top.hetzner.host.agents) zone viewers services;
                  inherit agentPolicyRefs;
                  zoneId = domains.${top.hetzner.host.agents.zone}.zoneId;
                }) agentsAccess.layer
              ))
              # The build cache's bucket and its domain (../cache).
              top.cache.layer
              # The Zero Trust organization (Access), team "kagamizo" (the
              # owner's choice, 2026-11-03): what status.mirazo.org and the
              # host's agents sit behind.
              {
                resource.cloudflare_zero_trust_organization.kagamizo = {
                  account_id = top.cloudflare.checked.accountId;
                  name = "kagamizo";
                  auth_domain = "kagamizo.cloudflareaccess.com";
                };
                # How the owner signs in: a one-time code mailed to the
                # address the policy names (declared, not Access's
                # implicit fallback).
                resource.cloudflare_zero_trust_access_identity_provider.otp = {
                  account_id = top.cloudflare.checked.accountId;
                  name = "One-time PIN";
                  type = "onetimepin";
                  config = { };
                };
              }
              # What the state adopts from Cloudflare (./imports.nix).
              {
                import = lib.mapAttrsToList (to: id: { inherit to id; }) (
                  lib.filterAttrs (to: _: statusOn || !(lib.hasSuffix ".status" to)) top.cloudflare.imports
                );
              }
            ];
      };

      # Inside secretspec: the profile's secrets are in the environment.
      run = pkgs.writeShellApplication {
        name = "infra-run";
        runtimeInputs = [
          tofu
          pkgs.jq
          pkgs.diffutils
          config.packages.pass-cli
          config.packages.statestore-run
          pkgs.bash
        ];
        text = ''
          : "''${CLOUDFLARE_API_TOKEN:?}" "''${TOFU_STATE_PASSPHRASE:?}"

          # HCL-quote the passphrase: JSON escaping plus escaped template markers.
          passphrase=$(jq -rn --arg p "$TOFU_STATE_PASSPHRASE" \
            '$p | tojson | gsub("\\$\\{"; "$${") | gsub("%\\{"; "%%{")')
          TF_ENCRYPTION=$(cat <<HCL
          key_provider "pbkdf2" "state" {
            passphrase = $passphrase
          }
          method "aes_gcm" "state" {
            keys = key_provider.pbkdf2.state
          }
          state {
            method   = method.aes_gcm.state
            enforced = true
          }
          plan {
            method   = method.aes_gcm.state
            enforced = true
          }
          HCL
          )
          export TF_ENCRYPTION

          work=$(mktemp -d)
          trap 'rm -rf "$work"' EXIT
          cp ${configs.cloudflare} "$work/main.tf.json"
          # The state lives in Proton Pass (statestore.backends.cloudflare),
          # served for this run; only `ci` may lock and write it.
          mode=()
          [ "$INFRA_PROFILE" = ci ] || mode=(--read-only)
          # The agents tunnel's token can only be read by a token that may
          # write tunnels: the read-only view plans around it (its output
          # shows as unknown), and only `ci` reads it (infra-tunnel-token).
          exclude=()
          [ "$INFRA_PROFILE" = ci ] || [ "''${1:-}" != plan ] ||
            exclude=(-exclude=data.cloudflare_zero_trust_tunnel_cloudflared_token.agents)
          status=0
          # The script's $0 and $@ are its own arguments, expanded inside.
          # shellcheck disable=SC2016
          statestore-run cloudflare "''${mode[@]}" -- bash -c '
            # stderr keeps stdout clean for `output -raw`.
            tofu -chdir="$0" init -input=false >&2 && tofu -chdir="$0" "$@"
          ' "$work" "$@" "''${exclude[@]}" || status=$?
          exit "$status"
        '';
      };
    in
    {
      # OpenTofu with the pinned Cloudflare provider; also feeds catalog/.
      packages.tofu = tofu;

      packages.infra = pkgs.writeShellApplication {
        name = "infra";
        runtimeInputs = [
          tofu
          pkgs.jq
          config.packages.pass-cli
          config.packages.secretspec
        ];
        # Builds only while every demand holds (R2 turned on for the cache).
        text = builtins.seq top.accounts.checked ''
          usage="usage: infra <ci|agent> <tofu args...>"
          profile=''${1:?$usage}
          shift
          case "$profile" in
            ci | agent) ;;
            *) echo "$usage" >&2; exit 2 ;;
          esac
          export PROTON_PASS_KEY_PROVIDER=''${PROTON_PASS_KEY_PROVIDER:-fs}
          # Under an agent token (CI's views), pass-cli refuses every command
          # without a stated reason; statestore's state reads run pass-cli too.
          export PROTON_PASS_AGENT_REASON="infra $profile: the Cloudflare state and the run's tokens"
          export INFRA_PROFILE=$profile INFRA_SPEC=${config.packages.secretspec-toml}
          exec secretspec run --file "$INFRA_SPEC" --profile "$profile" \
            --reason "''${SECRETSPEC_REASON:-infra $profile $*}" -- ${run}/bin/infra-run "$@"
        '';
      };

      # Offline schema check against the pinned provider; no credentials needed.
      checks.infra = pkgs.runCommand "infra-validate" { nativeBuildInputs = [ tofu ]; } ''
        export HOME=$TMPDIR
        ${lib.concatMapStrings (layer: ''
          mkdir ${layer}
          cp ${configs.${layer}} ${layer}/main.tf.json
          tofu -chdir=${layer} init -backend=false -input=false
          tofu -chdir=${layer} validate
        '') (lib.attrNames configs)}
        touch $out
      '';

      # Lean check: every agent team's Access service-token policy is attached
      # only to applications its tools justify, the owner's policy precedes
      # every token policy, and no token policy reaches the status page
      # (the owner's page only).
      checks.cloudflare-access =
        let
          q = builtins.toJSON;
          agentsAccess = import ./_agents-access.nix {
            inherit lib;
            inherit (top.cloudflare.checked) accountId;
            agents = top.governance.agents;
          };

          # Render a Lean Option String: some "x" or none.
          opt = v: if v == null then "none" else "some ${q v}";

          # Render a Lean ToolMapping value.
          renderTool = tool: app:
            "{ tool := ${q tool}, app := ${opt app} }";

          # Render a Lean AgentPolicy value.
          renderPolicy = agent: apps:
            "{ agent := ${q agent}, apps := [${lib.concatMapStringsSep ", " q apps}] }";

          toolAppData = lib.mapAttrsToList (tool: app: renderTool tool app) agentsAccess._toolAppMapping;
          agentPolicyData = lib.mapAttrsToList (agent: apps: renderPolicy agent apps) agentsAccess._agentAccessMapping;
          statusApp = "cloudflare_zero_trust_access_application.status";
          facts = ''
            namespace Kagamizo.Cloudflare

            /-- Every tool and the application it maps to, rendered by modules/cloudflare/infra.nix. -/
            def toolApp : List ToolMapping := [
            ${lib.concatMapStringsSep ",\n" (v: "  ${v}") toolAppData}
            ]

            /-- Every dsh agent and the application resource keys its policy reaches. -/
            def agentPolicies : List AgentPolicy := [
            ${lib.concatMapStringsSep ",\n" (v: "  ${v}") agentPolicyData}
            ]

            /-- The status page application resource key. -/
            def statusApp : String := ${q statusApp}

            /-- Every service token policy is attached only to applications the team's tools map to. -/
            theorem sound_access : sound toolApp agentPolicies statusApp = true := by
              decide +kernel

            /-- The owner's policy precedes every token policy (structural: owner at 1, agents at 2). -/
            theorem owner_first : ownerFirst agentPolicies = true := by
              decide +kernel

            /-- No token policy is attached to the status page (the owner's page only). -/
            theorem no_status : noStatusToken agentPolicies statusApp = true := by
              decide +kernel

            end Kagamizo.Cloudflare
          '';
        in
        pkgs.runCommand "cloudflare-access"
          {
            nativeBuildInputs = [ pkgs.lean4 ];
            inherit facts;
            passAsFile = [ "facts" ];
          }
          ''
            printf '%s\n' "$(cat ${./_lean/Access.lean})" > Check.lean
            cat "$factsPath" >> Check.lean
            lean Check.lean
            touch $out
          '';
    };
}
