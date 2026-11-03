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
  top = config;
  inherit (config.identity.checked) domains;
  statusOn = config.accounts.held.cloudflare.products ? zeroTrust;
  cli = import ../_lib/cli.nix {
    inherit lib;
    fx = inputs.nix-effects.lib;
  };
in
{
  # The layer's state, in the state vault every reader shares (proton.agents
  # gives ci editor, agents viewer).
  statestore.backends.cloudflare.vault = top.proton.infraVaults.state;

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
        # Served by statestore-run (../statestore) from Proton Pass.
        backend.http = { };
      };

      # Each layer is checked against the pinned provider (catalog/) before it
      # is written out.
      configs = lib.mapAttrs (name: c: pkgs.writeText "${name}.tf.json" (builtins.toJSON (cli.tofu c))) {
        cloudflare =
          lib.foldl' lib.recursiveUpdate (import ./_zones.nix { inherit lib domains terraform; })
            [
              # status.mirazo.org is served only behind Access: the whole
              # layer waits for the owner to turn Zero Trust on
              # (accounts.held.cloudflare.products.zeroTrust).
              (lib.optionalAttrs statusOn (
                import ./_status.nix {
                  inherit (top.cloudflare.checked) accountId;
                  zoneId = domains."mirazo.org".zoneId;
                  hostname = "status.mirazo.org";
                  viewers = [ "zach@mirazo.org" ];
                  html = config.site.statusHtml;
                }
              ))
              # The build cache's bucket and its domain (../cache).
              top.cache.layer
              # The Zero Trust organization (Access), team "kagamizo" (the
              # owner's choice, 2026-11-03): what status.mirazo.org and the
              # host's agents sit behind.
              {
                resource.cloudflare_zero_trust_organization.kagamizo = {
                  account_id = top.cloudflare.checked.accountId;
                  name = "kagamizo";
                  auth_domain = "kagamizo.cloudflareaccess.com";
                };
              }
              # What the state adopts from Cloudflare (./imports.nix).
              {
                import = lib.mapAttrsToList (to: id: { inherit to id; }) (
                  lib.filterAttrs (to: _: statusOn || !(lib.hasSuffix ".status" to)) top.cloudflare.imports
                );
              }
            ];
      };

      # Inside secretspec: the profile's secrets are in the environment.
      run = pkgs.writeShellApplication {
        name = "infra-run";
        runtimeInputs = [
          tofu
          pkgs.jq
          pkgs.diffutils
          config.packages.pass-cli
          config.packages.statestore-run
          pkgs.bash
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
          # The state lives in Proton Pass (statestore.backends.cloudflare),
          # served for this run; only `ci` may lock and write it.
          mode=()
          [ "$INFRA_PROFILE" = ci ] || mode=(--read-only)
          status=0
          # The script's $0 and $@ are its own arguments, expanded inside.
          # shellcheck disable=SC2016
          statestore-run cloudflare "''${mode[@]}" -- bash -c '
            # stderr keeps stdout clean for `output -raw`.
            tofu -chdir="$0" init -input=false >&2 && tofu -chdir="$0" "$@"
          ' "$work" "$@" || status=$?
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
        # Builds only while every demand holds (R2 turned on for the cache).
        text = builtins.seq top.accounts.checked ''
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
