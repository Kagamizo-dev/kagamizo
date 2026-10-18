# Cloudflare as code: each layer is plain Nix rendered to OpenTofu's JSON
# syntax, run by the `infra` app with secrets supplied by secretspec.
{ pkgs }:
let
  inherit (pkgs) lib;
  settings = import ./settings.nix;

  tofu = pkgs.opentofu.withPlugins (p: [ p.cloudflare_cloudflare ]);

  # Encrypted state in R2 (S3 API). Credentials come from AWS_ACCESS_KEY_ID /
  # AWS_SECRET_ACCESS_KEY; the encryption key from TOFU_STATE_PASSPHRASE.
  backend = layer: {
    required_providers.cloudflare = {
      source = "cloudflare/cloudflare";
      version = "~> 5.19";
    };
    backend.s3 = {
      bucket = settings.stateBucket;
      key = "${layer}.tfstate";
      region = "auto";
      endpoints.s3 = "https://${settings.accountId}.r2.cloudflarestorage.com";
      use_path_style = true;
      skip_credentials_validation = true;
      skip_region_validation = true;
      skip_requesting_account_id = true;
      skip_metadata_api_check = true;
      skip_s3_checksum = true;
    };
  };

  configs = lib.mapAttrs (name: config: pkgs.writeText "${name}.tf.json" (builtins.toJSON config)) {
    bootstrap = import ./bootstrap.nix {
      inherit lib settings backend;
      tokens = import ./tokens.nix;
    };
    cloudflare = import ./cloudflare.nix { inherit lib settings backend; };
  };

  placeholders = lib.any (lib.hasPrefix "REPLACE") [
    settings.accountId
    settings.zoneId
  ];
in
{
  inherit configs;

  # nix run .#infra -- <bootstrap|cloudflare> <tofu args...>
  app = pkgs.writeShellApplication {
    name = "infra";
    runtimeInputs = [
      tofu
      pkgs.jq
    ];
    text = ''
      usage="usage: infra <bootstrap|cloudflare> <tofu args...>"
      layer=''${1:?$usage}
      shift
      case "$layer" in
        bootstrap) config=${configs.bootstrap} ;;
        cloudflare) config=${configs.cloudflare} ;;
        *) echo "$usage" >&2; exit 2 ;;
      esac

      if ${lib.boolToString placeholders}; then
        echo "infra/settings.nix still has REPLACE placeholders; fill in accountId and zoneId." >&2
        exit 1
      fi
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
  check = pkgs.runCommand "infra-validate" { nativeBuildInputs = [ tofu ]; } ''
    export HOME=$TMPDIR
    ${lib.concatMapStrings (layer: ''
      mkdir ${layer}
      cp ${configs.${layer}} ${layer}/main.tf.json
      tofu -chdir=${layer} init -backend=false -input=false
      tofu -chdir=${layer} validate
    '') (lib.attrNames configs)}
    touch $out
  '';
}
