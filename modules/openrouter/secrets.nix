# The management key `openrouter apply` mints every key with, and where each
# minted key lands (openrouter.keys.*.profile).
let
  secret = import ../_lib/secret.nix;
in
{
  secrets.profiles = {
    # It cannot call models itself.
    openrouter = {
      defaults.providers = [ "kagamizo" ];
      OPENROUTER_MANAGEMENT_KEY = secret {
        kind = "api-token";
        issuer = "human:console-credential";
        description = "OpenRouter management key, made once in the dashboard (a Gap)";
        item = "openrouter-management-key";
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
