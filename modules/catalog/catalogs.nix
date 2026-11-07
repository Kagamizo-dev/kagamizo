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
#   _json/hetzner-api.json          Hetzner Cloud's API from its OpenAPI
#                                     spec (stamped with the one it was read
#                                     from; nix run .#hetzner-api-update):
#                                     every operation,
#                                     its parameters, body and response fields
#   _json/hcloud.json               every hcloud command and option
#   _json/hetzner-provider.json     every resource and data source of the
#                                     pinned OpenTofu hcloud provider
#   _json/pass-items.json           every Proton Pass item type's fields and
#                                     the custom field kinds, from the pinned
#                                     pass-cli's templates (with a session:
#                                     nix run .#pass-items-update), and the
#                                     app templates seen on real items
#   _json/rea.json                  REA's MCP tools (by family) and CLI
#                                     commands, generated from its pinned
#                                     source (modules/rea)
#   _json/rclone.json               every rclone backend and its typed options
#                                     (`rclone config providers`)
#   _json/icloudpd.json             every icloudpd option, from its --help
#   _json/pyicloud.json             pyicloud's services, their methods and
#                                     properties with their parameters,
#                                     asked of the pinned library
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
{
  self,
  inputs,
  lib,
  ...
}:
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

      # Hetzner Cloud's API from its published OpenAPI spec, pinned by hash: a
      # changed spec fails the fetch until the hash (and the catalog) move.

      hcloud = pkgs.runCommand "hcloud.json" { } ''
        export TMPDIR
        ${python} ${./_extract/hcloud.py} ${config.packages.hcloud}/bin/hcloud $out
      '';

      hetzner-provider = pkgs.runCommand "hetzner-provider.json" { } ''
        export HOME=$TMPDIR
        echo '{"terraform":{"required_providers":{"hcloud":{"source":"hetznercloud/hcloud"}}}}' > main.tf.json
        ${config.packages.tofu-hetzner}/bin/tofu init -backend=false -input=false >/dev/null
        ${config.packages.tofu-hetzner}/bin/tofu providers schema -json > schema.json
        ${python} ${./_extract/tofu.py} schema.json $out
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

      # The migration's readers (modules/migration/tools.nix), asked of the
      # pinned binaries themselves.
      rclone = pkgs.runCommand "rclone.json" { } ''
        ${python} ${./_extract/rclone.py} ${config.packages.rclone}/bin/rclone $out
      '';
      icloudpd = pkgs.runCommand "icloudpd.json" { } ''
        ${python} ${./_extract/icloudpd.py} ${config.packages.icloudpd}/bin/icloudpd $out
      '';
      pyicloud = pkgs.runCommand "pyicloud.json" { } ''
        ${config.packages.migration-python}/bin/python3 -I ${./_extract/pyicloud.py} $out
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
          name = "rclone.json";
          path = rclone;
        }
        {
          name = "icloudpd.json";
          path = icloudpd;
        }
        {
          name = "pyicloud.json";
          path = pyicloud;
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
          name = "hcloud.json";
          path = hcloud;
        }
        {
          name = "hetzner-provider.json";
          path = hetzner-provider;
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
      packages = {
        catalog-coverage = coverage;
        catalog = catalogs;
        pass-items-update = pkgs.writeShellApplication {
          name = "pass-items-update";
          runtimeInputs = [ pkgs.git ];
          text = ''
            cd "$(git rev-parse --show-toplevel)"
            ${python} ${./_extract/pass_items.py} ${config.packages.pass-cli}/bin/pass-cli \
              ${config.packages.pass-cli.version} modules/catalog/_json/pass-items.json
            git status --short modules/catalog/_json/pass-items.json
          '';
        };
        # Hetzner publishes its OpenAPI spec at one URL with no versions (its
        # info.version stays 1.0.0), so a hash pin breaks whenever it is
        # edited. The catalog is read from it here, outside the sandbox, and
        # stamped with the spec's SHA-256 and Last-Modified; the change
        # arrives as a reviewable diff of catalog/_json/hetzner-api.json.
        hetzner-api-update = pkgs.writeShellApplication {
          name = "hetzner-api-update";
          runtimeInputs = [
            pkgs.git
            pkgs.curl
            pkgs.coreutils
            pkgs.gnugrep
          ];
          text = ''
            cd "$(git rev-parse --show-toplevel)"
            dir=$(mktemp -d)
            trap 'rm -rf "$dir"' EXIT
            curl -fsS -D "$dir/headers" -o "$dir/spec.json" https://docs.hetzner.cloud/cloud.spec.json
            modified=$(grep -i '^last-modified:' "$dir/headers" | cut -d' ' -f2- | tr -d '\r')
            sha=$(sha256sum "$dir/spec.json" | cut -d' ' -f1)
            ${python} ${./_extract/hetzner_api.py} "$dir/spec.json" modules/catalog/_json/hetzner-api.json \
              --stamp "$sha" "$modified"
            git status --short modules/catalog/_json/hetzner-api.json
          '';
        };
        catalog-update = pkgs.writeShellApplication {
          name = "catalog-update";
          text = ''
            cd "$(git rev-parse --show-toplevel)"
            install -m 644 ${catalogs}/*.json modules/catalog/_json/
            git status --short modules/catalog/_json/
          '';
        };
      };

      checks = {
        catalog-coverage = coverage;

        # Proton Pass's item types need a signed-in session to read, so they
        # are extracted outside the sandbox (pass-items-update) and stamped
        # with the pass-cli they came from; this fails when the pin moves.
        catalog-pass-items =
          let
            stamped = (lib.importJSON ./_json/pass-items.json).passCli;
          in
          assert lib.assertMsg (stamped == config.packages.pass-cli.version)
            "catalog/_json/pass-items.json is from pass-cli ${stamped}, the pin is ${config.packages.pass-cli.version}: nix run .#pass-items-update";
          pkgs.runCommand "catalog-pass-items" { } "touch $out";

        # Every sandbox-extracted catalog matches its pinned tool; the
        # session-extracted pass-items.json is checked above instead, and
        # hetzner-api.json carries the spec it was read from.
        catalog = pkgs.runCommand "catalog-in-sync" { } ''
          if ! diff -r -x pass-items.json -x hetzner-api.json ${self}/modules/catalog/_json ${catalogs} >/dev/null; then
            echo "modules/catalog/_json does not match the pinned tools: nix run .#catalog-update" >&2
            exit 1
          fi
          touch $out
        '';
      };
    };
}
