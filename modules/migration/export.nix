# The migration's Phase 3 runners (./_src, Rust): each pinned tool run with
# its own session from Proton Pass, writing into a directory it ends with a
# manifest of (every file's size and SHA-256), which `migrate verify` holds
# a copy to. Every call is held to the tools' catalogs
# (../catalog/_json/{icloudpd,rclone,pyicloud}.json; checks.catalog-coverage).
#
#   nix run .#migrate -- login icloudpd      icloudpd's own trusted session
#   nix run .#migrate -- login rclone        rclone's iclouddrive remote
#       (each: the Apple ID's password piped from Proton Pass, Apple's code
#       relayed by the session into the FIFO this prints, the session kept
#       in the owner's Sessions vault)
#   nix run .#migrate -- photos DIR          icloudpd, originals and sidecars
#   nix run .#migrate -- drive DIR           rclone copy, then rclone check
#   nix run .#migrate -- notes DIR           pyicloud, HTML with attachments
#   nix run .#migrate -- reminders DIR       pyicloud, every list as JSON
#   nix run .#migrate -- verify DIR          the copy against its manifest
#
# The exports go to the host's staging volume (../hetzner, hetzner.volumes
# .staging) and from there to Proton Drive under /Archives/apple
# (./sources.nix). Running them here is the same program on a smaller disk.
{ lib, config, ... }:
let
  top = config;
  account = config.accounts.held.apple-mirazo;
  vault = config.identity.checked.entities.${account.owner}.vault;
  profile = "icloud";
  session =
    item: description:
    (import ../_lib/secret.nix) {
      kind = "oauth-session";
      issuer = "automation:migrate";
      needs = [ "approve-sign-in" ];
      inherit description item;
    }
    // {
      required = false;
    };
in
{
  secrets.profiles = {
    # On jingzo-host the same sessions live in the host's own vault, from
    # the delegations (../hetzner/credentials.nix): it never opens the
    # owner's.
    icloud-host = {
      defaults.providers = [ "host" ];
      ICLOUD_SESSION = session "icloud-session" "apple-mirazo's trusted iCloud session, the host's copy";
      ICLOUDPD_SESSION = session "icloudpd-session" "icloudpd's trusted iCloud session, the host's copy";
      RCLONE_ICLOUD_CONFIG = session "rclone-icloud-config" "rclone's iclouddrive remote, the host's copy";
    };
    ${profile} = {
      ICLOUDPD_SESSION = session "icloudpd-session" "icloudpd's trusted iCloud session (its cookie jar), base64";
      RCLONE_ICLOUD_CONFIG = session "rclone-icloud-config" "rclone's iclouddrive remote: the obscured password, trust token and cookies";
    };
    # The staging volume's LUKS key, generated on the host and kept in its
    # vault (./_host.nix).
    host.STAGING_LUKS_KEY =
      (import ../_lib/secret.nix) {
        kind = "encryption-key";
        issuer = "automation:migration-staging";
        description = "The migration staging volume's LUKS key, base64";
        item = "staging-luks-key";
      }
      // {
        required = false;
      };
  };

  governance.actions.apple = {
    icloudpd-sign-in = {
      effect = "session";
      description = "Sign icloudpd in to iCloud (a code from the owner's devices) and keep its session";
      command = "migrate login icloudpd";
    };
    rclone-sign-in = {
      effect = "session";
      description = "Sign rclone's iclouddrive remote in (a code from the owner's devices) and keep its config";
      command = "migrate login rclone";
    };
    export-photos = {
      effect = "read";
      description = "Every photo and video original with its XMP sidecar, by icloudpd, with a manifest";
      command = "migrate photos";
    };
    export-files = {
      effect = "read";
      description = "iCloud Drive copied whole by rclone and checked against the source, with a manifest";
      command = "migrate drive";
    };
    export-notes = {
      effect = "read";
      description = "Every note as archival HTML with its attachments, by pyicloud, with a manifest";
      command = "migrate notes";
    };
    export-reminders = {
      effect = "read";
      description = "Every reminder list as JSON, by pyicloud, with a manifest";
      command = "migrate reminders";
    };
  };

  perSystem =
    { pkgs, config, ... }:
    let
      run = pkgs.rustPlatform.buildRustPackage {
        pname = "migrate";
        version = "0.1.0";
        src = ./_src;
        cargoLock.lockFile = ./_src/Cargo.lock;
        meta.mainProgram = "migrate";
      };
      frozen = import ../_lib/frozen.nix {
        inherit lib pkgs;
        inherit (top) runtime;
      };
      inner = pkgs.writeShellApplication {
        name = "migrate";
        runtimeInputs = [
          run
          config.packages.icloudpd
          config.packages.rclone
          config.packages.migration-python
          config.packages.pass-cli
          config.packages.secretspec
          config.packages.governance-authorize
          pkgs.coreutils
          pkgs.gnutar
          pkgs.gzip
        ];
        text = builtins.seq top.migration.checked ''
          export PROTON_PASS_KEY_PROVIDER=''${PROTON_PASS_KEY_PROVIDER:-fs}
          usage="usage: migrate login <icloudpd|rclone> | photos DIR | drive DIR | notes DIR | reminders DIR | verify DIR"
          case "''${1:-} ''${2:-}" in
            "login icloudpd") governance-authorize apple:icloudpd-sign-in apple-mirazo ;;
            "login rclone") governance-authorize apple:rclone-sign-in apple-mirazo ;;
            "photos "?*) governance-authorize apple:export-photos apple-mirazo ;;
            "drive "?*) governance-authorize apple:export-files apple-mirazo ;;
            "notes "?*) governance-authorize apple:export-notes apple-mirazo ;;
            "reminders "?*) governance-authorize apple:export-reminders apple-mirazo ;;
            "verify "?*) ;;
            *) echo "$usage" >&2; exit 2 ;;
          esac
          private=$(mktemp -d)
          chmod 700 "$private"
          trap 'rm -rf "$private"' EXIT
          MIGRATE_PRIVATE=$private \
            MIGRATE_SECRETSPEC_FILE=${config.packages.secretspec-toml} \
            MIGRATE_PROFILE=${profile} \
            MIGRATE_LOGIN_VAULT=${lib.escapeShellArg vault} \
            MIGRATE_LOGIN_ITEM=${lib.escapeShellArg account.login.item} \
            MIGRATE_APPLE_ID=${account.login.email} \
            MIGRATE_CODE_FIFO=''${ICLOUD_CODE_FIFO:-/tmp/icloud-2fa-code} \
            MIGRATE_EXPORT_PY=${./_export.py} \
            MIGRATE_ICLOUDPD_VERSION=${config.packages.icloudpd.version} \
            MIGRATE_RCLONE_VERSION=${config.packages.rclone.version} \
            MIGRATE_PYICLOUD_VERSION=${lib.escapeShellArg config.catalog.sources.pyicloud.version} \
            migrate "$@"
        '';
      };
    in
    {
      packages = {
        migrate-run = run;
        migrate-inner = inner;
        migrate = frozen {
          name = "migrate";
          program = lib.getExe inner;
          packages = [ ];
        };
        # jingzo-host's runner (./_host.nix): the host's own profile and the
        # Apple login delegated into its vault. Its authorization is the
        # delegation (hetzner.host.credentials: declared, scoped, dated);
        # Cedar has no host principal yet (a Gap).
        migrate-host = pkgs.writeShellApplication {
          name = "migrate";
          runtimeInputs = [
            run
            config.packages.icloudpd
            config.packages.rclone
            config.packages.migration-python
            config.packages.pass-cli
            config.packages.secretspec
            pkgs.coreutils
            pkgs.gnutar
            pkgs.gzip
          ];
          text = builtins.seq top.migration.checked ''
            export PROTON_PASS_KEY_PROVIDER=fs
            export PROTON_PASS_AGENT_REASON="jingzo-host: the migration's exports (migrate $*)"
            private=$(mktemp -d)
            chmod 700 "$private"
            trap 'rm -rf "$private"' EXIT
            MIGRATE_PRIVATE=$private \
              MIGRATE_SECRETSPEC_FILE=${config.packages.secretspec-toml} \
              MIGRATE_PROFILE=icloud-host \
              MIGRATE_LOGIN_VAULT=${lib.escapeShellArg top.proton.infraVaults.host} \
              MIGRATE_LOGIN_ITEM=apple-mirazo-login \
              MIGRATE_APPLE_ID=${account.login.email} \
              MIGRATE_CODE_FIFO=/run/migrate-2fa-code \
              MIGRATE_EXPORT_PY=${./_export.py} \
              MIGRATE_ICLOUDPD_VERSION=${config.packages.icloudpd.version} \
              MIGRATE_RCLONE_VERSION=${config.packages.rclone.version} \
              MIGRATE_PYICLOUD_VERSION=${lib.escapeShellArg config.catalog.sources.pyicloud.version} \
              migrate "$@"
          '';
        };
      };
    };
}
