# secretspec.toml, generated from proton.infraVaults so vault names live in
# one place. The committed file must match; regenerate it with
#
#   nix build .#secretspec-toml && cp result secretspec.toml
#
# The rule: a secret lives with the identity it belongs to. Account-wide
# power (the Cloudflare root token, the bootstrap state, the registrar token,
# which spends money on the account) sits in your root vault; Kagamizo's own
# credentials (its GitHub organization) in Kagamizo's; CI and agents in their
# own vaults. `proton plan` diffs these references against Proton Pass.
{
  lib,
  config,
  self,
  ...
}:
let
  inherit (config.proton) infraVaults;

  secret = description: item: {
    inherit description;
    ref.item = item;
  };

  # The same variable names in every profile: what a token can do depends only
  # on which vault resolved it.
  state = access: {
    AWS_ACCESS_KEY_ID = secret "R2 state bucket key ID, ${access}" "r2-state-key-id";
    AWS_SECRET_ACCESS_KEY = secret "R2 state bucket secret, ${access}" "r2-state-secret";
  };

  spec = {
    project = {
      name = "nix-images";
      revision = "1.0";
    };

    providers = {
      root = "protonpass://${infraVaults.root}";
      kagamizo = "protonpass://${infraVaults.entity}";
      ci = "protonpass://${infraVaults.ci}";
      agents = "protonpass://${infraVaults.agents}";
    };

    profiles = {
      # Yours only: run by hand to mint or rotate the token profiles.
      bootstrap = {
        defaults.providers = [ "root" ];
        CLOUDFLARE_API_TOKEN = secret "Root token that can create API tokens (dashboard template: Create Additional Tokens)" "cloudflare-token";
        TOFU_STATE_PASSPHRASE = secret "Encrypts the bootstrap layer state (holds token values)" "tofu-state-passphrase";
      }
      // state "read and write";

      # Kagamizo's GitHub organization, declared with OpenTofu once it exists.
      github = {
        defaults.providers = [ "kagamizo" ];
        GITHUB_TOKEN = secret "Fine-grained token administering the kagamizo GitHub organization" "github-token";
      };

      # Yours only: buying domains (`registrar register`), which costs money.
      registrar = {
        defaults.providers = [ "root" ];
        CLOUDFLARE_API_TOKEN = secret "Token with Registrar write, minted by bootstrap" "cloudflare-registrar-token";
      };

      # GitHub Actions on master, behind the `cloudflare` environment.
      ci = {
        defaults.providers = [ "ci" ];
        CLOUDFLARE_API_TOKEN = secret "ci-apply token from the bootstrap layer" "cloudflare-token";
        TOFU_STATE_PASSPHRASE = secret "Encrypts the cloudflare layer state" "tofu-state-passphrase";
      }
      // state "read and write";

      # The agent fleet and PR plans: read everything, change nothing.
      agent = {
        defaults.providers = [ "agents" ];
        CLOUDFLARE_API_TOKEN = secret "agent-readonly token from the bootstrap layer" "cloudflare-token";
        TOFU_STATE_PASSPHRASE = secret "Same value as in the ci vault, so plans can read the cloudflare layer state" "tofu-state-passphrase";
        OPENROUTER_API_KEY = secret "OpenRouter key for the agent fleet" "openrouter-api-key" // {
          required = false;
        };
      }
      // state "read only";
    };
  };
in
{
  options.proton.secretspec = lib.mkOption {
    type = lib.types.raw;
    readOnly = true;
    description = "The secretspec declaration; secretspec.toml is rendered from it.";
  };
  config = {
    proton.secretspec = spec;

    perSystem =
      { pkgs, ... }:
      let
        toml = (pkgs.formats.toml { }).generate "secretspec.toml" spec;
        file = pkgs.runCommand "secretspec.toml" { } ''
          {
            echo "# Generated from parts/proton/secretspec.nix; edit that, not this."
            echo "# Values never live here: only names, descriptions and Proton Pass item titles."
            echo
            cat ${toml}
          } > $out
        '';
      in
      {
        packages.secretspec-toml = file;
        checks.secretspec-toml = pkgs.runCommand "secretspec-toml-in-sync" { } ''
          if ! diff -u ${self}/secretspec.toml ${file}; then
            echo "secretspec.toml is stale: nix build .#secretspec-toml && cp result secretspec.toml" >&2
            exit 1
          fi
          touch $out
        '';
      };
  };
}
