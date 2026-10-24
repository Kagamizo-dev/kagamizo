# What each tool can do, extracted from the pinned tool itself and committed
# under _json/, so nothing about a CLI or the provider is guessed:
#
#   _json/cf.json                   every cf command (arguments, options,
#                                     types, required) and its OAuth scopes
#   _json/cloudflare-provider.json  every OpenTofu resource and data source
#                                     of the pinned provider, per attribute
#   _json/pass-cli.json             every pass-cli command and option
#   _json/gh.json                   every gh command, argument and option
#   _json/mercury.json              every mercury command and option, read
#                                     from its pinned Go source
#   _json/mercury-api.json          Mercury's API as the pinned Go SDK has
#                                     it: every endpoint, type, field, enum,
#                                     and the endpoints each command calls
#   _json/public.json               every public command, argument and
#                                     option, from its click tree
#   _json/bridge.json               Proton Mail Bridge's flags and every
#                                     command of its CLI, from its pinned
#                                     source
#   _json/rea.json                  REA's MCP tools (by family) and CLI
#                                     commands, generated from its pinned
#                                     source (modules/rea)
#   _json/cdp.json                  every DevTools Protocol command (its
#                                     parameters, returns) and enum of the
#                                     pinned Chromium, asked of Chromium itself
#
# ../_lib/cli.nix types every invocation in this repo against them, and
# `checks.catalog-coverage` holds every raw call (shell lines, Rust's
# Command::new) to the same catalogs; its report, per module, is
#
#   nix build .#catalog-coverage && cat result
# Bumping a
# tool changes its catalog, so a version bump arrives as a reviewable diff;
# `nix flake check` fails until the committed catalogs match the pinned tools:
#
#   nix run .#catalog-update
{ self, inputs, ... }:
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

      # Read from the pinned source: its help is a drawn TUI.
      mercury = pkgs.runCommand "mercury.json" { } ''
        ${python} ${./_extract/mercury.py} ${inputs.mercury-cli} $out
      '';

      # Mercury's API surface from the Go SDK the CLI pins (its go.mod), and
      # each CLI command's endpoints from the CLI's own handlers.
      mercury-api = pkgs.runCommand "mercury-api.json" { } ''
        ${python} ${./_extract/mercury_api.py} \
          ${config.packages.mercury.goModules}/github.com/MercuryTechnologies/mercury-go \
          ${inputs.mercury-cli} ${self}/modules/catalog/_json/mercury.json $out
      '';

      # Walks the CLI's own click tree: its help is a drawn TUI too.
      public = pkgs.runCommand "public.json" { } ''
        export HOME=$TMPDIR
        ${
          pkgs.python3.withPackages (ps: [ (ps.toPythonModule config.packages.public) ])
        }/bin/python3 -I ${./_extract/public.py} $out
      '';

      # Chromium serves the protocol it speaks; ask the pinned one.
      cdp = pkgs.runCommand "cdp.json" { } ''
        export HOME=$TMPDIR FONTCONFIG_FILE=${pkgs.makeFontsConf { fontDirectories = [ ]; }}
        ${python} ${./_extract/cdp.py} ${pkgs.lib.getExe pkgs.chromium} $out
      '';

      bridge = pkgs.runCommand "bridge.json" { } ''
        ${python} ${./_extract/bridge.py} ${pkgs.protonmail-bridge.src} $out
      '';

      catalogs = pkgs.linkFarm "catalog" [
        {
          name = "bridge.json";
          path = bridge;
        }
        {
          name = "cdp.json";
          path = cdp;
        }
        {
          name = "mercury.json";
          path = mercury;
        }
        {
          name = "mercury-api.json";
          path = mercury-api;
        }
        {
          name = "rea.json";
          path = config.packages.rea-catalog;
        }
        {
          name = "public.json";
          path = public;
        }
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
      coverage = pkgs.runCommand "catalog-coverage" { } ''
        ${python} ${./_extract/coverage.py} ${self}/modules ${self}/modules/catalog/_json $out
      '';
    in
    {
      checks.catalog-coverage = coverage;
      packages = {
        catalog-coverage = coverage;
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
