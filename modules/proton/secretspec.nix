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

  secret = import ../_lib/secret.nix;

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
      host = "protonpass://${infraVaults.host}";
    }
    // lib.mapAttrs' (
      entity: vault: lib.nameValuePair "${entity}-sessions" "protonpass://${vault}"
    ) config.proton.sessionVaults;

    profiles = config.secrets.profiles;
  };
in
{
  options.secrets.profiles = lib.mkOption {
    type = lib.types.attrsOf (lib.types.attrsOf lib.types.anything);
    default = { };
    description = ''
      secretspec profiles, merged from every module: each declares the
      secrets it uses, as VARIABLE = import ../_lib/secret.nix "what" "item"
      under the profile that holds them, plus the profile's defaults.
    '';
  };

  options.proton.secretspec = lib.mkOption {
    type = lib.types.raw;
    readOnly = true;
    description = "The secretspec declaration; secretspec.toml is rendered from it.";
  };
  config = {
    proton.secretspec = spec;

    # Yours: the Proton Pass agent tokens `proton apply` creates, kept until
    # they are handed to their consumer (GitHub Actions secrets, Orca).
    secrets.profiles.proton-agents = {
      defaults.providers = [ "root" ];
    }
    // lib.mapAttrs' (
      name: a:
      lib.nameValuePair a.secret (secret "Proton Pass agent token `${name}`" "pass-agent-${name}")
    ) config.proton.agents;

    perSystem =
      { pkgs, ... }:
      let
        toml = (pkgs.formats.toml { }).generate "secretspec.toml" spec;
        file = pkgs.runCommand "secretspec.toml" { } ''
          {
            echo "# Generated from each module's secrets.profiles (modules/proton/secretspec.nix); edit those, not this."
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
