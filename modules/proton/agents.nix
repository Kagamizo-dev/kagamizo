# Proton Pass agent tokens, one per consumer. Each opens its home vault plus
# exactly the access listed, at the role listed. Roles and expirations are the
# values pass-cli itself accepts (catalog/pass-cli.json), and vaults must be
# declared ones, so a typo fails evaluation instead of a login.
#
# `proton apply` creates the missing agents, stores each token in your root
# vault under `secret` (secretspec profile `proton-agents`) and grants the
# access; `proton plan` shows the difference.
{
  lib,
  config,
  inputs,
  ...
}:
let
  inherit (lib) mkOption types;
  cli = import ../_lib/cli.nix {
    inherit lib;
    fx = inputs.nix-effects.lib;
  };
  inherit (config.proton) vaults infraVaults;
  Vault = types.enum vaults;

  agent = types.submodule {
    options = {
      vault = mkOption {
        type = Vault;
        description = "The vault the agent is created on.";
      };
      expiration = mkOption {
        type = types.enum (cli.passCliChoices "agent create" "expiration");
      };
      access = mkOption {
        type = types.listOf (
          types.submodule {
            options = {
              vault = mkOption { type = Vault; };
              role = mkOption { type = types.enum (cli.passCliChoices "agent access grant" "role"); };
            };
          }
        );
        default = [ ];
        description = "Further vaults the agent may open, each at one role.";
      };
      secret = mkOption {
        type = types.strMatching "[A-Z][A-Z0-9_]*";
        description = "Variable the token is stored as in the proton-agents profile.";
      };
    };
  };
in
{
  options.proton.agents = mkOption {
    type = types.attrsOf agent;
    default = { };
  };

  config.accounts.demands = [
    {
      account = "proton";
      capability = "passAccessTokens";
      need = true;
      why = "proton.agents (agent tokens) and secretspec in CI";
    }
  ];

  config.proton.agents = {
    # GitHub Actions on main: applies, so it writes the state.
    nix-images-ci = {
      vault = infraVaults.ci;
      expiration = "6m";
      access = [
        {
          vault = infraVaults.state;
          role = "editor";
        }
      ];
      secret = "PROTON_PASS_CI_TOKEN";
    };

    # PR plans: read the state, change nothing.
    nix-images-plan = {
      vault = infraVaults.agents;
      expiration = "6m";
      access = [
        {
          vault = infraVaults.state;
          role = "viewer";
        }
      ];
      secret = "PROTON_PASS_AGENT_TOKEN";
    };

    # The always-on host: reads its own vault at boot, nothing else.
    kagamizo-host = {
      vault = infraVaults.host;
      expiration = "6m";
      secret = "PROTON_PASS_HOST_TOKEN";
    };

    # The Orca agent fleet: the same view as plans, renewed monthly.
    orca-fleet = {
      vault = infraVaults.agents;
      expiration = "1m";
      access = [
        {
          vault = infraVaults.state;
          role = "viewer";
        }
      ];
      secret = "PROTON_PASS_ORCA_TOKEN";
    };
  };
}
