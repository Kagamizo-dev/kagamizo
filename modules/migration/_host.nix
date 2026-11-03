# The migration's staging on the host (NixOS; imported by ../hetzner/host.nix
# with the `migrate` package): the Hetzner volume (hetzner.volumes.staging)
# encrypted and mounted, and the exports run on a timer into it.
#
# The volume is found by Hetzner's own device name (one scsi-0HC_Volume_*),
# LUKS-formatted on first use with a key the host generates and keeps in
# Proton Pass (the host profile's STAGING_LUKS_KEY), and mounted at
# `mount`. The exports need Proton Pass: the host signs in with its agent
# token (pass-cli login --pat), read from `tokenFile`, which nothing
# delivers yet (a Gap, modules/cloudflare/README.md); until it is there,
# the units stay idle and say so.
{
  migrate,
  secretspecToml,
  secretspec,
  passCli,
}:
{
  lib,
  pkgs,
  config,
  ...
}:
let
  inherit (lib) mkOption types;
  cfg = config.migration.host;
in
{
  options.migration.host = {
    mount = mkOption {
      type = types.str;
      default = "/var/lib/migration/staging";
    };
    tokenFile = mkOption {
      type = types.str;
      default = "/var/lib/kagamizo/host-token";
      description = "The host's Proton Pass agent token (PROTON_PASS_HOST_TOKEN), mode 600.";
    };
    classes = mkOption {
      type = types.listOf (
        types.enum [
          "photos"
          "drive"
          "notes"
          "reminders"
        ]
      );
      default = [
        "notes"
        "reminders"
        "drive"
        "photos"
      ];
    };
    at = mkOption {
      type = types.str;
      default = "*-*-* 02:10:00";
      description = "When the exports run (systemd calendar); each class in turn.";
    };
  };

  config = {
    environment.systemPackages = [ migrate ];

    systemd = {
      services.migration-staging = {
        description = "The migration's staging volume: LUKS, mounted";
        wantedBy = [ "multi-user.target" ];
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        path = [
          pkgs.cryptsetup
          pkgs.e2fsprogs
          pkgs.util-linux
          pkgs.coreutils
          secretspec
          passCli
        ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          # The network can come up after the unit starts; try again.
          Restart = "on-failure";
          RestartSec = 30;
        };
        script = ''
          set -euo pipefail
          [ -r ${cfg.tokenFile} ] || { echo "migration-staging: no host token at ${cfg.tokenFile}; idle" >&2; exit 0; }
          devs=(/dev/disk/by-id/scsi-0HC_Volume_*)
          [ ''${#devs[@]} -eq 1 ] && [ -e "''${devs[0]}" ] || { echo "migration-staging: expected one Hetzner volume, found ''${#devs[@]}" >&2; exit 1; }
          dev=''${devs[0]}
          export PROTON_PASS_KEY_PROVIDER=fs HOME=/root
          # An agent token: pass-cli refuses its commands without a reason.
          export PROTON_PASS_AGENT_REASON="jingzo-host: migration staging and exports"
          pass-cli login --pat "$(cat ${cfg.tokenFile})" >/dev/null
          key=$(mktemp -p /run)
          chmod 600 "$key"
          trap 'rm -f "$key"' EXIT
          if secretspec get STAGING_LUKS_KEY --file ${secretspecToml} --profile host --reason "migration-staging: the volume's key" >"$key" 2>/dev/null && [ -s "$key" ]; then
            :
          else
            head -c 64 /dev/urandom | base64 -w0 >"$key"
            secretspec set STAGING_LUKS_KEY --file ${secretspecToml} --profile host --reason "migration-staging: keep the volume's key" --from-file "$key" >/dev/null
          fi
          if ! cryptsetup isLuks "$dev"; then
            cryptsetup luksFormat --batch-mode --key-file "$key" "$dev"
            cryptsetup open --key-file "$key" "$dev" staging
            mkfs.ext4 -L staging /dev/mapper/staging
          else
            cryptsetup open --key-file "$key" "$dev" staging
          fi
          mkdir -p ${cfg.mount}
          mountpoint -q ${cfg.mount} || mount /dev/mapper/staging ${cfg.mount}
          chmod 700 ${cfg.mount}
        '';
      };

      services.migration-export = {
        description = "The migration's exports off iCloud into the staging volume";
        after = [ "migration-staging.service" ];
        requires = [ "migration-staging.service" ];
        path = [
          migrate
          passCli
          pkgs.coreutils
          pkgs.util-linux
        ];
        serviceConfig.Type = "oneshot";
        script = ''
          set -euo pipefail
          [ -r ${cfg.tokenFile} ] || { echo "migration-export: no host token; idle" >&2; exit 0; }
          mountpoint -q ${cfg.mount} || { echo "migration-export: staging not mounted" >&2; exit 1; }
          export PROTON_PASS_KEY_PROVIDER=fs HOME=/root
          # An agent token: pass-cli refuses its commands without a reason.
          export PROTON_PASS_AGENT_REASON="jingzo-host: migration staging and exports"
          pass-cli login --pat "$(cat ${cfg.tokenFile})" >/dev/null
          for class in ${lib.concatStringsSep " " cfg.classes}; do
            migrate "$class" ${cfg.mount}/apple/"$class"
            migrate verify ${cfg.mount}/apple/"$class"
          done
        '';
      };
      timers.migration-export = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = cfg.at;
          Persistent = true;
        };
      };
    };
  };
}
