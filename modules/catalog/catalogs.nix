# What each tool can do, extracted from the pinned tool itself and committed
# under _json/, so nothing about a CLI or the provider is guessed:
#
#   _json/cf.json                   every cf command (arguments, options,
#                                     types, required) and its OAuth scopes
#   _json/cloudflare-provider.json  every OpenTofu resource and data source
#                                     of the pinned provider, per attribute
#   _json/pass-cli.json             every pass-cli command and option
#   _json/gh.json                   every gh command, argument and option
#
# ../_lib/cli.nix types every invocation in this repo against them. Bumping a
# tool changes its catalog, so a version bump arrives as a reviewable diff;
# `nix flake check` fails until the committed catalogs match the pinned tools:
#
#   nix run .#catalog-update
{ self, ... }:
{
  perSystem =
    { pkgs, config, ... }:
    let
      python = "${pkgs.python3}/bin/python3 -I";
      cfDist = "${config.packages.cf}/lib/node_modules/cf/dist";

      cf = pkgs.runCommand "cf.json" { } ''
        scopes=$(grep -l account_api_tokens:create ${cfDist}/*.mjs | head -1)
        ${python} ${./_extract/cf.py} ${cfDist}/_meta "$scopes" $out
      '';

      cloudflare-provider = pkgs.runCommand "cloudflare-provider.json" { } ''
        export HOME=$TMPDIR
        echo '{"terraform":{"required_providers":{"cloudflare":{"source":"cloudflare/cloudflare"}}}}' > main.tf.json
        ${config.packages.tofu}/bin/tofu init -backend=false -input=false >/dev/null
        ${config.packages.tofu}/bin/tofu providers schema -json > schema.json
        ${python} ${./_extract/tofu.py} schema.json $out
      '';

      pass-cli = pkgs.runCommand "pass-cli.json" { } ''
        export HOME=$TMPDIR PROTON_PASS_KEY_PROVIDER=fs
        ${python} ${./_extract/pass_cli.py} ${config.packages.pass-cli}/bin/pass-cli $out
      '';

      gh = pkgs.runCommand "gh.json" { } ''
        export HOME=$TMPDIR GH_NO_UPDATE_NOTIFIER=1
        ${python} ${./_extract/gh.py} ${config.packages.gh}/bin/gh $out
      '';

      catalogs = pkgs.linkFarm "catalog" [
        {
          name = "cf.json";
          path = cf;
        }
        {
          name = "cloudflare-provider.json";
          path = cloudflare-provider;
        }
        {
          name = "pass-cli.json";
          path = pass-cli;
        }
        {
          name = "gh.json";
          path = gh;
        }
      ];
    in
    {
      packages = {
        catalog = catalogs;
        catalog-update = pkgs.writeShellApplication {
          name = "catalog-update";
          text = ''
            cd "$(git rev-parse --show-toplevel)"
            install -m 644 ${catalogs}/*.json modules/catalog/_json/
            git status --short modules/catalog/_json/
          '';
        };
      };

      checks.catalog = pkgs.runCommand "catalog-in-sync" { } ''
        if ! diff -r ${self}/modules/catalog/_json ${catalogs} >/dev/null; then
          echo "modules/catalog/_json does not match the pinned tools: nix run .#catalog-update" >&2
          exit 1
        fi
        touch $out
      '';
    };
}
