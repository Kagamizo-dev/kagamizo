# The management key `openrouter apply` mints every key with, and where each
# minted key lands (openrouter.keys.*.profile).
let
  secret = import ../_lib/secret.nix;
in
{
  secrets.profiles = {
    # It cannot call models itself.
    openrouter = {
      defaults.providers = [ "jingzo-logins" ];
      OPENROUTER_MANAGEMENT_KEY = secret {
        kind = "api-token";
        issuer = "human:console-credential";
        description = "OpenRouter management key, made once in the dashboard and pasted by the owner into the prepared API-credential item";
        item = "openrouter-management-key";
        template = "api-credential";
        field = "Secret";
      };
    };
    agent.OPENROUTER_API_KEY =
      secret {
        kind = "api-token";
        issuer = "automation:openrouter";
        description = "OpenRouter key for the agent fleet";
        item = "openrouter-api-key";
      }
      // {
        required = false;
      };
    # The research loops' key (modules/research): jingzo's, in its sessions vault.
    research = {
      defaults.providers = [ "jingzo-sessions" ];
      OPENROUTER_API_KEY =
        secret {
          kind = "api-token";
          issuer = "automation:openrouter";
          description = "OpenRouter key for the research loops, minted by `openrouter apply`";
          item = "openrouter-research-key";
        }
        // {
          required = false;
        };
    };
    host.OPENROUTER_API_KEY =
      secret {
        kind = "api-token";
        issuer = "automation:openrouter";
        description = "OpenRouter key for chat and code, minted by `openrouter keys`";
        item = "openrouter-api-key";
      }
      // {
        required = false;
      };
  };
}
