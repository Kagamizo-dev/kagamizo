# Cloudflare as code: each layer is plain Nix rendered to OpenTofu's JSON
# syntax, run by the `infra` app with secrets supplied by secretspec.
#
#   nix run .#infra -- <ci|agent> <tofu args...>
#
# The first word is the secretspec profile, i.e. the view: `agent` reads (PR
# plans), `ci` applies. The state is a local file fetched from the state vault
# (TOFU_STATE) and, under `ci`, written back when the run changed it, so Proton
# Pass holds it like every other secret. Tokens come first, from `bootstrap`.
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
in
{
  perSystem =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    let
      tofu = pkgs.opentofu.withPlugins (p: [ p.cloudflare_cloudflare ]);

      # State stays local to the run; `infra` moves it in and out of Proton
      # Pass. Encrypted with TOFU_STATE_PASSPHRASE before it leaves tofu.
      terraform = {
        required_providers.cloudflare = {
          source = "cloudflare/cloudflare";
          version = "~> 5.19";
        };
      };

      # Each layer is checked against the pinned provider (catalog/) before it
      # is written out.
      configs = lib.mapAttrs (name: c: pkgs.writeText "${name}.tf.json" (builtins.toJSON (cli.tofu c))) {
        cloudflare = import ./_zones.nix { inherit lib domains terraform; };
      };

      # Inside secretspec: the profile's secrets are in the environment.
      run = pkgs.writeShellApplication {
        name = "infra-run";
        runtimeInputs = [
          tofu
          pkgs.jq
          pkgs.diffutils
          config.packages.secretspec
          config.packages.pass-cli
        ];
        text = ''
          : "''${CLOUDFLARE_API_TOKEN:?}" "''${TOFU_STATE_PASSPHRASE:?}"

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
          cp ${configs.cloudflare} "$work/main.tf.json"
          if [ -n "''${TOFU_STATE:-}" ]; then
            printf %s "$TOFU_STATE" >"$work/terraform.tfstate"
            cp "$work/terraform.tfstate" "$work/before"
          fi
          unset TOFU_STATE
          # stderr keeps stdout clean for `output -raw`.
          tofu -chdir="$work" init -input=false >&2
          status=0
          tofu -chdir="$work" "$@" || status=$?

          # Write a changed state back, even after a partial failure, so
          # what was created is never forgotten. Only `ci` holds the state
          # vault as editor; anything else changing it is a bug.
          if [ -f "$work/terraform.tfstate" ] && ! cmp -s "$work/terraform.tfstate" "$work/before" 2>/dev/null; then
            if [ "$INFRA_PROFILE" != ci ]; then
              echo "infra: the $INFRA_PROFILE view changed the state; not saving it" >&2
              exit 1
            fi
            secretspec set TOFU_STATE --file "$INFRA_SPEC" --profile ci \
              --from-file "$work/terraform.tfstate" >/dev/null
            echo "infra: state saved to Proton Pass" >&2
          fi
          exit "$status"
        '';
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
          config.packages.pass-cli
          config.packages.secretspec
        ];
        text = ''
          usage="usage: infra <ci|agent> <tofu args...>"
          profile=''${1:?$usage}
          shift
          case "$profile" in
            ci | agent) ;;
            *) echo "$usage" >&2; exit 2 ;;
          esac
          export PROTON_PASS_KEY_PROVIDER=''${PROTON_PASS_KEY_PROVIDER:-fs}
          export INFRA_PROFILE=$profile INFRA_SPEC=${config.packages.secretspec-toml}
          exec secretspec run --file "$INFRA_SPEC" --profile "$profile" \
            --reason "''${SECRETSPEC_REASON:-infra $profile $*}" -- ${run}/bin/infra-run "$@"
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
