# The build cache (Roadmap epic 4, approved): a Cloudflare R2 bucket served
# over HTTPS at cache.kagamizo.com, which every machine reads with no secret
# (a Nix substituter), and which CI fills on every push to any branch with
# everything the flake builds, signed. A fresh cloud session, a runner or
# the host then downloads what CI already built instead of rebuilding the
# Rust crates, the Lean checks, the catalogs and the host closure.
#
#   nix run .#cache-key          once: generate the signing key into the cache
#                                vault and print its public half, which goes
#                                into cache.publicKey and flake.nix's nixConfig
#   nix run .#cache-push         build every check and package and copy their
#                                closures to the bucket, signed (CI's job)
#   nix build .#cache-nix-conf   the nix.conf lines a machine pulls with; the
#                                session-start hook writes them
#
# The bucket and its domain are OpenTofu in the Cloudflare layer (applied by
# `infra ci apply`, like status.mirazo.org). The push keys are R2's S3 pair,
# derived by bootstrap from the `cache-push` token (../cloudflare/tokens.nix),
# in the cache vault with the signing key; CI holds that vault's agent token
# as a repository secret (../github/kagamizo.nix).
{ lib, config, ... }:
let
  inherit (lib) mkOption types;
  cfg = config.cache;
  secret = import ../_lib/secret.nix;
  zone = config.identity.checked.domains.${cfg.zone};
  accountId = config.cloudflare.checked.accountId;
  keyName = "${cfg.host}-1";
  flakeText = builtins.readFile ../../flake.nix;
in
{
  options.cache = {
    bucket = mkOption {
      type = types.strMatching "[a-z0-9][a-z0-9-]*";
      default = "kagamizo-nix-cache";
    };
    zone = mkOption {
      type = types.str;
      default = "kagamizo.com";
      description = "The declared domain the cache's hostname is on.";
    };
    host = mkOption {
      type = types.str;
      default = "cache.${cfg.zone}";
    };
    location = mkOption {
      # R2's location hints, from the provider's docs.
      type = types.enum [
        "apac"
        "eeur"
        "enam"
        "weur"
        "wnam"
        "oc"
      ];
      default = "enam";
    };
    publicKey = mkOption {
      type = types.nullOr (types.strMatching "${lib.escapeRegex keyName}:[A-Za-z0-9+/=]+");
      # Generated 2026-11-01 (cache-key); its secret half is in the cache vault.
      default = "cache.kagamizo.com-1:CI8baL7Y24eA45LdMEPk6s/v0IXA3uL59vkIpAfjO7c=";
      description = "The signing key's public half (cache-key prints it); null until generated.";
    };
    layer = mkOption {
      type = types.raw;
      readOnly = true;
      description = "The bucket and its domain, for the Cloudflare OpenTofu layer.";
    };
  };

  config = {
    # The bucket needs R2 turned on in the account, a step only the owner
    # can take (accounts.held.cloudflare.products.r2).
    accounts.demands = [
      {
        account = "cloudflare";
        product = "r2";
        need = true;
        why = "cache: the build cache's R2 bucket";
      }
    ];
    cache.layer.resource = {
      cloudflare_r2_bucket.cache = {
        account_id = accountId;
        name = cfg.bucket;
        inherit (cfg) location;
      };
      # Public reads: a custom domain on the zone makes the bucket readable
      # over HTTPS, which is all a substituter needs.
      cloudflare_r2_custom_domain.cache = {
        account_id = accountId;
        bucket_name = cfg.bucket;
        domain = cfg.host;
        enabled = true;
        zone_id = zone.zoneId;
        min_tls = "1.2";
        depends_on = [ "cloudflare_r2_bucket.cache" ];
      };
    };

    secrets.profiles.cache = {
      defaults.providers = [ "cache" ];
      CLOUDFLARE_API_TOKEN = secret {
        kind = "api-token";
        issuer = "automation:bootstrap";
        needs = [ "approve-sign-in" ];
        description = "cache-push token, minted by bootstrap (R2 write only)";
        item = "cloudflare-token";
      };
      R2_ACCESS_KEY_ID = secret {
        kind = "identifier";
        issuer = "automation:bootstrap";
        description = "The cache-push token's id: R2's S3 access key id";
        item = "r2-cache-access-key-id";
      };
      R2_SECRET_ACCESS_KEY = secret {
        kind = "api-token";
        issuer = "automation:bootstrap";
        description = "SHA-256 of the cache-push token: R2's S3 secret access key";
        item = "r2-cache-secret-access-key";
      };
      NIX_CACHE_SIGNING_KEY = secret {
        kind = "encryption-key";
        issuer = "automation:cache-key";
        description = "The build cache's Nix signing key (${keyName})";
        item = "nix-cache-signing-key";
      };
    };

    # Every push to any branch: build it all, push it all. PRs from forks
    # have no secrets and are not pushes, so they never write the cache.
    ci.workflows.cache = {
      description = "Every check and package of the push, built and copied signed to the build cache (modules/cache), so machines pull instead of rebuilding.";
      on.push = { };
      jobs.push = {
        name = "build and push to ${cfg.host}";
        runner = "linux-x86_64-kvm";
        timeoutMinutes = 180;
        steps = [
          { passCli = "2.4.2"; }
          {
            name = "Log in to Proton Pass (cache vault)";
            env.PROTON_PASS_PERSONAL_ACCESS_TOKEN.secret = "PROTON_PASS_CACHE_TOKEN";
            env.PROTON_PASS_KEY_PROVIDER = "fs";
            run = "pass-cli login";
          }
          {
            name = "cache-push";
            env.PROTON_PASS_KEY_PROVIDER = "fs";
            run = "nix run .#cache-push";
          }
          # The performance records (modules/perf): every target rebuilt
          # from scratch on the runner's clock and held to its record.
          {
            name = "perf-measure";
            run = "nix run .#perf-measure -- perf.jsonl";
          }
          {
            name = "perf-check";
            run = "nix run .#perf-check -- perf.jsonl";
          }
          {
            name = "Keep the measurements";
            always = true;
            artifact = {
              name = "perf";
              path = "perf.jsonl";
            };
          }
        ];
      };
    };

    perSystem =
      {
        pkgs,
        config,
        system,
        ...
      }:
      let
        spec = config.packages.secretspec-toml;
        # What CI builds and pushes: every check and package of this system,
        # by name, as declared here (the list is this module's eval of them).
        targets =
          map (n: ".#checks.${system}.${n}") (lib.attrNames config.checks)
          ++ map (n: ".#packages.${system}.${n}") (
            lib.attrNames (lib.filterAttrs (n: _: !lib.hasPrefix "cache-" n) config.packages)
          );
        store = "s3://${cfg.bucket}?endpoint=https://${accountId}.r2.cloudflarestorage.com&region=auto&compression=zstd";
        pushRun = pkgs.writeShellApplication {
          name = "cache-push-run";
          runtimeInputs = [
            pkgs.nix
            pkgs.coreutils
          ];
          text = ''
            : "''${R2_ACCESS_KEY_ID:?}" "''${R2_SECRET_ACCESS_KEY:?}" "''${NIX_CACHE_SIGNING_KEY:?}"
            export AWS_ACCESS_KEY_ID=$R2_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY=$R2_SECRET_ACCESS_KEY
            key=$(mktemp)
            chmod 600 "$key"
            trap 'rm -f "$key"' EXIT
            printf %s "$NIX_CACHE_SIGNING_KEY" >"$key"
            unset NIX_CACHE_SIGNING_KEY R2_SECRET_ACCESS_KEY
            echo "cache-push: building ${toString (lib.length targets)} targets" >&2
            mapfile -t paths < <(nix build --no-link --print-out-paths ${lib.concatStringsSep " " targets})
            echo "cache-push: copying ''${#paths[@]} outputs and their closures to ${cfg.host}" >&2
            nix copy --to "${store}&secret-key=$key" "''${paths[@]}"
            echo "cache-push: done" >&2
          '';
        };
      in
      {
        packages = {
          cache-push = pkgs.writeShellApplication {
            name = "cache-push";
            runtimeInputs = [
              config.packages.secretspec
              config.packages.pass-cli
            ];
            text = ''
              export PROTON_PASS_KEY_PROVIDER=''${PROTON_PASS_KEY_PROVIDER:-fs}
              exec secretspec run --file ${spec} --profile cache --reason "cache-push" -- ${lib.getExe pushRun}
            '';
          };

          cache-key = pkgs.writeShellApplication {
            name = "cache-key";
            runtimeInputs = [
              pkgs.nix
              config.packages.secretspec
              config.packages.pass-cli
              pkgs.coreutils
            ];
            text = ''
              export PROTON_PASS_KEY_PROVIDER=''${PROTON_PASS_KEY_PROVIDER:-fs}
              if ! secretspec get NIX_CACHE_SIGNING_KEY --file ${spec} --profile cache --reason "cache-key: is there one" >/dev/null 2>&1; then
                # Generated by nix and piped into Proton Pass: never printed.
                nix key generate-secret --key-name ${keyName} |
                  secretspec set NIX_CACHE_SIGNING_KEY --file ${spec} --profile cache \
                    --reason "cache-key: the signing key" --from-file /dev/stdin >/dev/null
                echo "cache-key: signing key generated into the cache vault" >&2
              fi
              echo "cache-key: public key (declare as cache.publicKey and in flake.nix nixConfig):" >&2
              secretspec get NIX_CACHE_SIGNING_KEY --file ${spec} --profile cache --reason "cache-key: public half" |
                nix key convert-secret-to-public
            '';
          };

          # What a machine pulls with; empty until the key is declared.
          cache-nix-conf = pkgs.writeText "cache-nix.conf" (
            lib.optionalString (cfg.publicKey != null) ''
              extra-substituters = https://${cfg.host}
              extra-trusted-public-keys = ${cfg.publicKey}
            ''
          );
        };

        # flake.nix's nixConfig names the cache once the key is declared, so
        # CI (accept-flake-config) pulls from it too.
        checks.cache-declared = pkgs.runCommand "cache-declared" (
          assert lib.assertMsg
            (
              cfg.publicKey == null
              || (lib.hasInfix "https://${cfg.host}" flakeText && lib.hasInfix cfg.publicKey flakeText)
            )
            "modules/cache: cache.publicKey is set but flake.nix's nixConfig does not name https://${cfg.host} and the key";
          { }
        ) "touch $out";
      };
  };
}
