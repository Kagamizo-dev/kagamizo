# Where every catalog comes from, at which version: one entry per file in
# ./_json, each version read from the pin itself (a package's version, a
# flake input's tag, the stamp a session-extracted catalog carries), never
# written by hand.
#
#   packages.catalog-sources       the table, as JSON (the Lean model and
#                                  ../lean take versions from it)
#   modules/catalog/README.md      the table, rendered; checks.catalog-sources
#                                  fails when it is stale or a catalog has
#                                  no source:  nix run .#catalog-readme
{
  inputs,
  lib,
  ...
}:
let
  json = ./_json;
  catalogs = map (lib.removeSuffix ".json") (
    lib.attrNames (lib.filterAttrs (n: _: lib.hasSuffix ".json" n) (builtins.readDir json))
  );
  stamp = n: lib.importJSON (json + "/${n}.json");
  # mercury-go, the SDK the CLI's go.mod requires.
  mercurySdk =
    let
      line = lib.findFirst (l: lib.hasInfix "MercuryTechnologies/mercury-go " l) null (
        lib.splitString "\n" (builtins.readFile "${inputs.mercury-cli}/go.mod")
      );
    in
    if line == null then
      throw "catalog/sources.nix: mercury-cli's go.mod requires no mercury-go"
    else
      lib.last (lib.splitString " " (lib.trim line));
  # A flake input's tag and revision, as flake.lock pins them.
  lock = (lib.importJSON ../../flake.lock).nodes;
  tagOf =
    input:
    let
      n = lock.${input};
    in
    "${lib.removePrefix "refs/tags/" (n.original.ref or "")} (${lib.substring 0 12 n.locked.rev})";
in
{
  perSystem =
    { pkgs, config, ... }:
    let
      inherit (config.catalog) sources;
      table = {
        cf = {
          from = "npm `cf`";
          version = config.packages.cf.version;
        };
        cloudflare-provider = {
          from = "OpenTofu cloudflare/cloudflare provider (nixpkgs)";
          version = pkgs.opentofu.plugins.cloudflare_cloudflare.version;
        };
        pass-cli = {
          from = "pass-cli release binary";
          version = config.packages.pass-cli.version;
        };
        pass-items = {
          from = "pass-cli's templates, read with a session; app templates as observed";
          version = "${(stamp "pass-items").passCli} (app templates: ${
            lib.concatStringsSep ", " (
              lib.mapAttrsToList (n: t: "${n}, ${t.source}") (stamp "pass-items").appTemplates
            )
          })";
        };
        gh = {
          from = "gh (nixpkgs)";
          version = pkgs.gh.version;
        };
        mercury = {
          from = "MercuryTechnologies/mercury-cli";
          version = tagOf "mercury-cli";
        };
        mercury-api = {
          from = "MercuryTechnologies/mercury-go, as mercury-cli's go.mod requires";
          version = mercurySdk;
        };
        public = {
          from = "PublicDotCom/publicdotcom-cli";
          version = tagOf "publicdotcom-cli";
        };
        bridge = {
          from = "protonmail-bridge source (nixpkgs)";
          version = pkgs.protonmail-bridge.version;
        };
        hcloud = {
          from = "hcloud";
          version = config.packages.hcloud.version;
        };
        hetzner-provider = {
          from = "OpenTofu hetznercloud/hcloud provider (nixpkgs)";
          version = pkgs.opentofu.plugins.hetznercloud_hcloud.version;
        };
        hetzner-api = {
          from = "docs.hetzner.cloud/cloud.spec.json (unversioned upstream)";
          version =
            let
              s = (stamp "hetzner-api").api.spec;
            in
            "sha256 ${lib.substring 0 16 s.sha256}…, ${s.lastModified}";
        };
        rea = {
          from = "morluto/rea";
          version = tagOf "rea";
        };
        rclone = {
          from = "rclone (nixpkgs)";
          inherit (config.packages.rclone) version;
        };
        icloudpd = {
          from = "icloud-photos-downloader/icloud_photos_downloader";
          version = tagOf "icloudpd-src";
        };
        cdp = {
          from = "the pinned Chromium's /json/protocol";
          version = "Chromium ${pkgs.chromium.version}, protocol ${(stamp "cdp").protocol}";
        };
      };
      missing = lib.subtractLists (lib.attrNames sources) catalogs;
      unknown = lib.subtractLists catalogs (lib.attrNames sources);
      empty = lib.attrNames (lib.filterAttrs (_: s: s.version == "") sources);
      readme = pkgs.writeText "README.md" ''
        # Catalogs

        Every tool and API the modules use, as its pinned version states it
        (`./_json`, extracted from the pin itself; `../lean` renders each into
        Lean). Generated from `sources.nix`: `nix run .#catalog-readme`.

        | Catalog | From | Version |
        |---|---|---|
        ${lib.concatMapStrings (n: "| ${n} | ${sources.${n}.from} | ${sources.${n}.version} |\n") (
          lib.attrNames sources
        )}
        Two have no upstream versions and are stamped by content instead:
        Hetzner's OpenAPI spec (its SHA-256 and Last-Modified;
        `nix run .#hetzner-api-update`) and Proton Pass's app templates (the
        item and date each was read from).
      '';
    in
    {
      options.catalog.sources = lib.mkOption {
        type = lib.types.attrsOf (
          lib.types.submodule {
            options = {
              from = lib.mkOption { type = lib.types.str; };
              version = lib.mkOption { type = lib.types.str; };
            };
          }
        );
        readOnly = true;
        description = "Every catalog's source and pinned version, read from the pin.";
      };
      config = {
        catalog.sources = table;
        packages = {
          catalog-sources = pkgs.writeText "catalog-sources.json" (builtins.toJSON sources);
          catalog-readme = pkgs.writeShellApplication {
            name = "catalog-readme";
            runtimeInputs = [ pkgs.git ];
            text = ''
              cd "$(git rev-parse --show-toplevel)"
              install -m 644 ${readme} modules/catalog/README.md
              git status --short modules/catalog/README.md
            '';
          };
        };
        checks.catalog-sources =
          assert lib.assertMsg (
            missing == [ ]
          ) "catalog/sources.nix: no source for ${lib.concatStringsSep ", " missing}";
          assert lib.assertMsg (unknown == [ ])
            "catalog/sources.nix: sources for catalogs that do not exist: ${lib.concatStringsSep ", " unknown}";
          assert lib.assertMsg (
            empty == [ ]
          ) "catalog/sources.nix: no version found for ${lib.concatStringsSep ", " empty}";
          pkgs.runCommand "catalog-sources" { } ''
            if ! diff -q ${readme} ${./README.md} >/dev/null; then
              echo "modules/catalog/README.md is stale: nix run .#catalog-readme" >&2
              exit 1
            fi
            touch $out
          '';
      };
    };
}
