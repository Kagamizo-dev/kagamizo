# Agent teams' Cloudflare Access service tokens and policies, so each team may
# reach only the services its tools justify.
#
# Tool → application mapping (a typed attrset so a tool outside the enum
# fails evaluation at the point of use).  Values are the application resource
# keys used by _agents.nix (agents-<name>), matching the agentPolicies side,
# derived from the application's declared service name (chat, harness).
#
#   repo   → null                 (GitHub, not behind Access)
#   matrix → "agents-chat"        (chat.jingzo.org: Element Web and Matrix)
#   shell  → "agents-harness"     (harness.jingzo.org: dsh web UI, shell)
#   web    → "agents-harness"     (dsh's web tool uses the same app)
#   twin   → "agents-harness"     (twin team's CAD and inventory tools)
#   comfy  → null                 (ComfyUI — no Access yet; no GPU)
#
# Each agent whose harness is "dsh" gets:
#   - one cloudflare_zero_trust_access_service_token "agents-<name>"
#   - one cloudflare_zero_trust_access_policy "agents-<name>" (decision
#     non_identity) that includes that token
#   - that policy is attached (after the owner's policy at precedence 2) only
#     to the applications the agent's tools map to
#
# The token's client id and secret are OpenTofu outputs; the apply writes them
# to Proton Pass (Kagamizo-Host-State) following the pattern of the tunnel
# token (infra-tunnel-token) and the matrix-seed logins.
#
# There is no service token for "status" — that is the owner's page only.
{
  lib,
  accountId,
  agents, # the governance.agents attrset (all agents, not just dsh)
}:
let
  inherit (builtins)
    attrNames
    ;

  # The application resource key for each tunnel hostname (from _agents.nix).
  # Both toolApp values and the agentPolicies list use this same form so the
  # Lean check compares identifiers from one source.
  appKeyForService = name: "agents-${name}";

  # ---------------------------------------------------------------------------
  # Tool → application mapping.  Every tool in governance.options.tools must
  # appear here; a tool absent from this set fails evaluation.  A null value
  # means the tool needs no Access application (e.g. repo → GitHub).
  # Values are full resource keys (agents-<name>) matching what _agents.nix
  # uses for its cloudflare_zero_trust_access_application resources.
  # ---------------------------------------------------------------------------
  toolApp = {
    repo = null; # GitHub, not behind Access
    matrix = appKeyForService "chat";
    shell = appKeyForService "harness";
    web = appKeyForService "harness";
    twin = appKeyForService "harness";
    comfy = null; # ComfyUI — not behind Access yet (GPU not provisioned)
  };

  # Collect dsh agents only.
  dshAgents = lib.filterAttrs (_: a: a.harness == "dsh") agents;

  # For each dsh agent, compute the set of application resource keys its
  # policy should be attached to.  toolApp already uses full resource keys
  # (agents-<name>), so we collect them directly from each non-null entry.
  agentAppKeys = lib.mapAttrs (
    _name: agent:
    let
      fromTools = lib.filter (t: toolApp.${t} != null) agent.tools;
      apps = lib.unique (map (t: toolApp.${t}) fromTools);
    in
    apps
  ) dshAgents;

  # Only agents with at least one app get tokens (pure-repo agents like
  # "review" get no Access token — they use GitHub credentials).
  agentsWithApps = lib.filterAttrs (_: apps: apps != [ ]) agentAppKeys;

  # ---------------------------------------------------------------------------
  # Build the agentPolicyRefs for _agents.nix: for each application, the extra
  # policy refs (id, precedence) to append after the owner's policy.
  # ---------------------------------------------------------------------------
  agentPolicyRefs = lib.foldl' (
    acc: agentName:
    let
      apps = agentAppKeys.${agentName};
      policyRef = {
        id = "\${cloudflare_zero_trust_access_policy.agents-${agentName}.id}";
        precedence = 2;
      };
    in
    lib.foldl' (
      acc': appKey:
      acc'
      // {
        ${appKey} = (acc'.${appKey} or [ ]) ++ [ policyRef ];
      }
    ) acc apps
  ) { } (attrNames agentsWithApps);

in
{
  # Layer configuration for OpenTofu (resource blocks and outputs).
  # infra.nix merges only this .layer into the cloudflare layer, keeping
  # helper attributes (mapping, policyRefs) out of the rendered JSON.
  layer = {
    resource =
      let
        # Service tokens — built as resource.<type>.<name> per the check's
        # expectation (two-level nesting: resource.cloudflare_* = { name = … }).
        tokenType = lib.mapAttrs' (name: _: lib.nameValuePair "agents-${name}" {
          account_id = accountId;
          name = "agents-${name}";
        }) agentsWithApps;

        # Policies that include the service token (decision = non_identity).
        policyType = lib.mapAttrs' (name: _: lib.nameValuePair "agents-${name}" {
          account_id = accountId;
          name = "agents: ${name}";
          decision = "non_identity";
          include = [
            {
              service_token = {
                token_id = "\${cloudflare_zero_trust_access_service_token.agents-${name}.id}";
              };
            }
          ];
        }) agentsWithApps;
      in
      {
        cloudflare_zero_trust_access_service_token = tokenType;
        cloudflare_zero_trust_access_policy = policyType;
      };

    # OpenTofu outputs for the CI apply to capture and store in Proton Pass.
    output = lib.mapAttrs' (name: _: {
      name = "agents-service-token-${name}";
      value = {
        value = {
          client_id = "\${cloudflare_zero_trust_access_service_token.agents-${name}.client_id}";
          client_secret = "\${cloudflare_zero_trust_access_service_token.agents-${name}.client_secret}";
        };
        sensitive = true;
      };
    }) agentsWithApps;
  };

  inherit agentPolicyRefs;

  # ---------------------------------------------------------------
  # Exported for the Lean check: agent→application-key mapping.
  # Checked by checks.cloudflare-access (./_lean/).
  # ---------------------------------------------------------------
  _agentAccessMapping = agentAppKeys;
  _toolAppMapping = toolApp;
}
