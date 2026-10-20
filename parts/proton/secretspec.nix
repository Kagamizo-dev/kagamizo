# secretspec.toml, generated from proton.infraVaults so vault names live in
# one place. The committed file must match; regenerate it with
#
#   nix build .#secretspec-toml && cp result secretspec.toml
#
# The rule: a secret lives with the identity it belongs to. Account-wide
# power (minting tokens, buying domains) is your `cloudflare-login` session and
# is never stored; Kagamizo's own credentials (its GitHub organization) sit in
# Kagamizo's vault; CI and agents in their own vaults, written by `bootstrap`.
# `proton plan` diffs these references against Proton Pass.
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
      kagamizo = "protonpass://${infraVaults.entity}";
      ci = "protonpass://${infraVaults.ci}";
      agents = "protonpass://${infraVaults.agents}";
    };

    profiles = {
      # Kagamizo's GitHub organization, declared with OpenTofu once it exists.
      github = {
        defaults.providers = [ "kagamizo" ];
        GITHUB_TOKEN = secret "Fine-grained token administering the kagamizo GitHub organization" "github-token";
      };

      # GitHub Actions on master, behind the `cloudflare` environment.
      ci = {
        defaults.providers = [ "ci" ];
        CLOUDFLARE_API_TOKEN = secret "ci-apply token, minted by bootstrap" "cloudflare-token";
        TOFU_STATE_PASSPHRASE = secret "Encrypts the cloudflare layer state" "tofu-state-passphrase";
      }
      // state "read and write";

      # The agent fleet and PR plans: read everything, change nothing.
      agent = {
        defaults.providers = [ "agents" ];
        CLOUDFLARE_API_TOKEN = secret "agent-readonly token, minted by bootstrap" "cloudflare-token";
        TOFU_STATE_PASSPHRASE = secret "Same value as in the ci vault, so plans can read the state" "tofu-state-passphrase";
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
