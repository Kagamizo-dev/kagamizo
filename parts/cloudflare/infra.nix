# Cloudflare as code: each layer is plain Nix rendered to OpenTofu's JSON
# syntax, run by the `infra` app with secrets supplied by secretspec.
#
#   nix run .#infra -- cloudflare <tofu args...>
#
# The tokens and the state bucket come first, from `bootstrap` (bootstrap.nix).
{
  config,
  lib,
  inputs,
  ...
}:
let
  inherit (config.identity.checked) domains;
  cli = import ../_lib/cli.nix {
    inherit lib;
    fx = inputs.nix-effects.lib;
  };
  cloudflare = config.cloudflare.checked;
in
{
  perSystem =
    { pkgs, lib, ... }:
    let
      tofu = pkgs.opentofu.withPlugins (p: [ p.cloudflare_cloudflare ]);

      # Encrypted state in R2 (S3 API). Credentials come from AWS_ACCESS_KEY_ID /
      # AWS_SECRET_ACCESS_KEY; the encryption key from TOFU_STATE_PASSPHRASE.
      backend = layer: {
        required_providers.cloudflare = {
          source = "cloudflare/cloudflare";
          version = "~> 5.19";
        };
        backend.s3 = {
          bucket = cloudflare.stateBucket;
          key = "${layer}.tfstate";
          region = "auto";
          endpoints.s3 = "https://${cloudflare.accountId}.r2.cloudflarestorage.com";
          use_path_style = true;
          skip_credentials_validation = true;
          skip_region_validation = true;
          skip_requesting_account_id = true;
          skip_metadata_api_check = true;
          skip_s3_checksum = true;
        };
      };

      # Each layer is checked against the pinned provider (catalog/) before it
      # is written out.
      configs = lib.mapAttrs (name: c: pkgs.writeText "${name}.tf.json" (builtins.toJSON (cli.tofu c))) {
        cloudflare = import ./_zones.nix { inherit lib domains backend; };
      };
    in
    {
      # OpenTofu with the pinned Cloudflare provider; also feeds catalog/.
      packages.tofu = tofu;

      packages.infra = pkgs.writeShellApplication {
        name = "infra";
        runtimeInputs = [
          tofu
          pkgs.jq
        ];
        text = ''
          usage="usage: infra cloudflare <tofu args...>"
          layer=''${1:?$usage}
          shift
          case "$layer" in
            cloudflare) config=${configs.cloudflare} ;;
            *) echo "$usage" >&2; exit 2 ;;
          esac

          hint="run it through secretspec, e.g. secretspec run --profile agent -- nix run .#infra -- cloudflare plan"
          : "''${CLOUDFLARE_API_TOKEN:?$hint}" "''${AWS_ACCESS_KEY_ID:?$hint}"
          : "''${AWS_SECRET_ACCESS_KEY:?$hint}" "''${TOFU_STATE_PASSPHRASE:?$hint}"

          # HCL-quote the passphrase: JSON escaping plus escaped template markers.
          passphrase=$(jq -rn --arg p "$TOFU_STATE_PASSPHRASE" \
            '$p | tojson | gsub("\\$\\{"; "$${") | gsub("%\\{"; "%%{")')
          TF_ENCRYPTION=$(cat <<HCL
          key_provider "pbkdf2" "state" {
            passphrase = $passphrase
          }
          method "aes_gcm" "state" {
            keys = key_provider.pbkdf2.state
          }
          state {
            method   = method.aes_gcm.state
            enforced = true
          }
          plan {
            method   = method.aes_gcm.state
            enforced = true
          }
          HCL
          )
          export TF_ENCRYPTION

          work=$(mktemp -d)
          trap 'rm -rf "$work"' EXIT
          cp "$config" "$work/main.tf.json"
          # stderr keeps stdout clean for `output -raw`.
          tofu -chdir="$work" init -input=false >&2
          tofu -chdir="$work" "$@"
        '';
      };

      # Offline schema check against the pinned provider; no credentials needed.
      checks.infra = pkgs.runCommand "infra-validate" { nativeBuildInputs = [ tofu ]; } ''
        export HOME=$TMPDIR
        ${lib.concatMapStrings (layer: ''
          mkdir ${layer}
          cp ${configs.${layer}} ${layer}/main.tf.json
          tofu -chdir=${layer} init -backend=false -input=false
          tofu -chdir=${layer} validate
        '') (lib.attrNames configs)}
        touch $out
      '';
    };
}
