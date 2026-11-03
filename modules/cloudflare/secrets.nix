# What the OpenTofu layers run with: a Cloudflare token per view, minted by
# `bootstrap`, and the state. The state and its passphrase live in the state
# vault every reader shares (the state itself is statestore's,
# ../statestore): CI holds it as editor, plans and agents as
# viewer (proton.agents). The same variable names everywhere, so what a
# process can do depends only on which vault resolved it.
_:
let
  secret = import ../_lib/secret.nix;
  state = {
    TOFU_STATE_PASSPHRASE =
      secret {
        kind = "encryption-key";
        issuer = "automation:bootstrap";
        description = "Encrypts the OpenTofu state and plans";
        item = "tofu-state-passphrase";
      }
      // {
        providers = [ "state" ];
      };
  };
in
{
  secrets.profiles = {
    # The account token that mints every other one (bootstrap): made once
    # by the owner in the dashboard with only "Account API Tokens: Edit",
    # and pasted into its prepared API-credential item. It replaces the cf
    # device sign-in, which can never hold billing and loses scopes the
    # approver unticks.
    cloudflare-root = {
      defaults.providers = [ "root" ];
      CLOUDFLARE_ROOT_TOKEN =
        secret {
          kind = "api-token";
          issuer = "human:console-credential";
          description = "Cloudflare account token with Account API Tokens: Edit, for bootstrap";
          item = "cloudflare-root-token";
          template = "api-credential";
          field = "Secret";
        }
        // {
          required = false;
        };
    };
    # GitHub Actions on main, behind the `cloudflare` environment.
    ci = {
      defaults.providers = [ "ci" ];
      CLOUDFLARE_API_TOKEN = secret {
        kind = "api-token";
        issuer = "automation:bootstrap";
        needs = [ "approve-sign-in" ];
        description = "ci-apply token, minted by bootstrap";
        item = "cloudflare-token";
      };
    }
    // state;

    # The agent fleet and PR plans: read everything, change nothing.
    agent = {
      defaults.providers = [ "agents" ];
      CLOUDFLARE_API_TOKEN = secret {
        kind = "api-token";
        issuer = "automation:bootstrap";
        needs = [ "approve-sign-in" ];
        description = "agent-readonly token, minted by bootstrap";
        item = "cloudflare-token";
      };
    }
    // state;

    # The tunnel the host serves chat and code through, from the access layer.
    host = {
      defaults.providers = [ "host" ];
      TUNNEL_TOKEN =
        secret {
          kind = "api-token";
          issuer = "automation:infra";
          description = "Cloudflare Tunnel token for chat and code, from the access layer";
          item = "tunnel-token";
        }
        // {
          required = false;
        };
    };
  };
}
