# What the OpenTofu layers run with: a Cloudflare token per view, minted by
# `bootstrap`, and the state. The state and its passphrase live in the state
# vault every reader shares: CI holds it as editor, plans and agents as
# viewer (proton.agents). The same variable names everywhere, so what a
# process can do depends only on which vault resolved it.
_:
let
  secret = import ../_lib/secret.nix;
  state = {
    TOFU_STATE_PASSPHRASE = secret "Encrypts the OpenTofu state and plans" "tofu-state-passphrase" // {
      providers = [ "state" ];
    };
    TOFU_STATE = secret "The encrypted OpenTofu state, written by `infra ci apply`" "tofu-state" // {
      providers = [ "state" ];
      # Absent until the first apply.
      required = false;
    };
  };
in
{
  secrets.profiles = {
    # GitHub Actions on main, behind the `cloudflare` environment.
    ci = {
      defaults.providers = [ "ci" ];
      CLOUDFLARE_API_TOKEN = secret "ci-apply token, minted by bootstrap" "cloudflare-token";
    }
    // state;

    # The agent fleet and PR plans: read everything, change nothing.
    agent = {
      defaults.providers = [ "agents" ];
      CLOUDFLARE_API_TOKEN = secret "agent-readonly token, minted by bootstrap" "cloudflare-token";
    }
    // state;

    # The tunnel the host serves chat and code through, from the access layer.
    host = {
      defaults.providers = [ "host" ];
      TUNNEL_TOKEN =
        secret "Cloudflare Tunnel token for chat and code, from the access layer" "tunnel-token"
        // {
          required = false;
        };
    };
  };
}
