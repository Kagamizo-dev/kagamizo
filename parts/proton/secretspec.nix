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

  # The OpenTofu state and its passphrase live in the state vault, which every
  # state reader shares: CI holds it as editor, plans and agents as viewer
  # (proton.agents). The same variable names everywhere, so what a process can
  # do depends only on which vault resolved it.
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
      state = "protonpass://${infraVaults.state}";
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
      }
      // state;

      # The agent fleet and PR plans: read everything, change nothing.
      agent = {
        defaults.providers = [ "agents" ];
        CLOUDFLARE_API_TOKEN = secret "agent-readonly token, minted by bootstrap" "cloudflare-token";
        OPENROUTER_API_KEY = secret "OpenRouter key for the agent fleet" "openrouter-api-key" // {
          required = false;
        };
      }
      // state;

      # Yours: the Proton Pass agent tokens `proton apply` creates, kept until
      # they are handed to their consumer (GitHub Actions secrets, Orca).
      proton-agents = {
        defaults.providers = [ "root" ];
      }
      // lib.mapAttrs' (
        name: a:
        lib.nameValuePair a.secret (secret "Proton Pass agent token `${name}`" "pass-agent-${name}")
      ) config.proton.agents;
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
