# Who may do what, declared once and compiled to Cedar (./cedar.nix):
#
#   governance.controllers.<entity> = [ <person> ... ]
#       the people who act for an entity: they may do anything to its
#       accounts, through the same wrappers the agents use (a person
#       always controls their own)
#   governance.actions.<provider>.<tool> = { effect; description; }
#       every operation a wrapper exposes, typed by what it does: read,
#       write, spend, destroy, session (signing in), move-login (moving an
#       account's login onto its declared address: the one kind of action
#       the login rule lets a controller run on a mismatched account), or
#       probe (actively testing the account's own surface for weaknesses:
#       granted only to a penetration tester, on its scope; ../security)
#   governance.agents.<name> = { serves; purpose; personas; grants; }
#       an agent identity: one Proton Pass agent token, one Cedar principal,
#       serving exactly one entity, holding only the grants listed
#
# The base layer (./cedar.nix) holds whatever is declared here: an agent
# never spends, destroys or signs in, and never touches another entity's
# accounts, whatever its grants say.
{
  lib,
  config,
  ...
}:
let
  inherit (lib) mkOption types;
  entities = config.identity.checked.entities;
  people = lib.attrNames (lib.filterAttrs (_: e: e.kind == "person") entities);
  effects = [
    "read"
    "write"
    "spend"
    "destroy"
    "session"
    "move-login"
    "probe"
  ];
  cfg = config.governance;

  action = types.submodule {
    options = {
      effect = mkOption { type = types.enum effects; };
      description = mkOption {
        type = types.str;
        default = "";
      };
      command = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "The command for it, program first (`cards spend`); null is `<provider> call <tool>`.";
      };
    };
  };

  grant = types.submodule {
    options = {
      account = mkOption {
        type = types.enum (lib.attrNames config.accounts.held);
        description = "A declared account; it must belong to the entity the agent serves.";
      };
      effects = mkOption {
        type = types.nonEmptyListOf (
          types.enum [
            "read"
            "write"
            "probe"
          ]
        );
        description = "What the agent may do to it. Spending, destroying and signing in are never granted to an agent; probing only to a penetration tester (../security).";
      };
      why = mkOption { type = types.str; };
    };
  };

  agent = types.submodule {
    options = {
      serves = mkOption {
        type = types.enum (lib.attrNames entities);
        description = "The one entity this agent works for.";
      };
      purpose = mkOption { type = types.str; };
      personas = mkOption {
        type = types.nonEmptyListOf (types.strMatching "[a-z-]+/[a-z0-9-]+");
        description = "agency-agents personas (division/file, no .md) the agent runs as OpenCode subagents.";
      };
      grants = mkOption {
        type = types.listOf grant;
        default = [ ];
      };
      # The plan of 2026-11-04: what each agent runs on and may propose.
      model = mkOption {
        type = types.enum config.openrouter.models;
        default = config.openrouter.defaultModel;
        defaultText = "openrouter.defaultModel";
        description = "The model it starts on (tier 2 unless its tasks say otherwise).";
      };
      key = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "The OpenRouter key it spends (openrouter.keys); null is its entity's swarm key.";
      };
      budgetUsdPerMonth = mkOption {
        # 0: it runs no model (tier 0 tools only), so it takes no share.
        type = types.ints.unsigned;
        # Three swarms share each entity's $20 swarm key.
        default = 3;
        description = "Its share of the key's monthly cap; Lean checks the shares fit (modules/agents).";
      };
      changeClasses = mkOption {
        type = types.listOf (types.enum (lib.attrNames config.governance.changeClasses));
        default = [ ];
        description = "The classes of change it may propose as pull requests (./changes.nix).";
      };
      tools = mkOption {
        type = types.listOf (
          types.enum [
            "shell"
            "web"
            "repo"
            "matrix"
            "twin"
            "comfy"
            # Reading our own surfaces without a person signing in: the
            # shell, the published files and the status page.
            "os"
            "files"
            "status"
          ]
        );
        default = [ ];
        description = "The tool sets it gets in its harness.";
      };
      harness = mkOption {
        type = types.enum [
          "dsh"
          "opencode"
          "orca"
        ];
        default = "orca";
        description = "Where it runs: DeepSeek Harness teams, OpenCode, or an Orca swarm.";
      };
    };
  };
in
{
  options.governance = {
    effects = mkOption {
      type = types.listOf types.str;
      readOnly = true;
      default = effects;
    };
    controllers = mkOption {
      type = types.attrsOf (types.listOf (types.enum people));
      default = { };
    };
    actions = mkOption {
      type = types.attrsOf (types.attrsOf action);
      default = { };
    };
    agents = mkOption {
      type = types.attrsOf agent;
      default = { };
    };
    problems = mkOption {
      type = types.listOf types.str;
      description = "Declarations the types alone cannot reject; any one fails `governance-cedar`.";
    };
  };

  config.governance.problems = lib.filter (p: p != "") (
    lib.concatLists (
      lib.mapAttrsToList (
        name: a:
        map (
          g:
          let
            held = config.accounts.held.${g.account};
          in
          lib.optionalString (
            held.owner != a.serves
          ) "governance.agents.${name}: ${g.account} belongs to ${held.owner}, not ${a.serves}"
          +
            lib.optionalString (!(cfg.actions ? ${held.provider}))
              "governance.agents.${name}: ${g.account} is a ${held.provider} account, and no ${held.provider} actions are declared"
        ) a.grants
      ) cfg.agents
    )
  );
}
