# Installing jingzo-host: nixos-anywhere (nix-community, pinned with
# nixpkgs) over SSH, from the host-install workflow, inside a dated window.
#
#   hetzner.host.install.publicKey   the install key's public half; its
#                                    private half is a Proton Pass SSH key
#                                    item, Kagamizo-Install/jingzo-host-install,
#                                    generated there by pass-cli
#   hetzner.host.install.window      { until = "YYYY-MM-DD"; } while SSH may
#                                    reach the server (the firewall rule in
#                                    ./infra.nix); null closes it. The plan
#                                    refuses a window past its date.
#
#   nix run .#host-install -- <ipv4>
#       reads the private key from Proton Pass into a mode-600 file (never
#       printed), runs nixos-anywhere --flake .#jingzo-host against
#       root@<ipv4>: it boots NixOS's installer in memory (kexec), partitions
#       the disk as declared (disko, ./host.nix), installs, reboots. The
#       installed system runs no SSH server.
#
# The workflow (.github/workflows/host-install.yml) signs pass-cli in with
# the host-install agent's token (PROTON_PASS_HOST_INSTALL_TOKEN), which
# opens Kagamizo-Install and nothing else.
{ lib, config, ... }:
let
  inherit (lib) mkOption types;
  vault = config.proton.infraVaults.install;
  item = "jingzo-host-install";
in
{
  options.hetzner.host.install = {
    publicKey = mkOption {
      type = types.strMatching "ssh-ed25519 [A-Za-z0-9+/=]+( .*)?";
      description = "The install key's public half (Proton Pass: ${vault}/${item}).";
    };
    window = mkOption {
      type = types.nullOr (
        types.submodule {
          options.until = mkOption {
            type = types.strMatching "[0-9]{4}-[0-9]{2}-[0-9]{2}";
            description = "The last day SSH may reach the server; the plan refuses after it.";
          };
        }
      );
      default = null;
      description = "While set, the firewall admits SSH for nixos-anywhere; null closes it.";
    };
  };

  config = {
    hetzner.host.install = {
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIF4o1biNsiYTdl40/PDI5xOPjGA1H5FFD6wot5JPn3ie jingzo-host install (nixos-anywhere), modules/hetzner/install.nix";
      # Closed. Installs: 2026-11-03 (host-install runs 41568360740, the
      # first, and 41573145877, which handed the host its token). Open it
      # again, dated, only to reinstall.
      # Closed. Installs on 2026-11-03: host-install runs 41568360740 (the
      # first), 41573145877 (with its token), 41575267127 (resolved, the
      # console report). Open it again, dated, only to reinstall.
      # Closed. On 2026-11-03 the host was installed (host-install runs
      # 41568360740 to 41582003588) and read from rescue (host-rescue) until
      # it signed in and kept its volume key. Open it again, dated, only to
      # reinstall or rescue.
      window = null;
    };

    perSystem =
      { pkgs, config, ... }:
      {
        # Read the installed system from Hetzner's rescue Linux, without a
        # reinstall: boot rescue with the install key (enable_rescue,
        # reset; the pinned API), mount the disk, print the host's token
        # state and its journal (NixOS's own journalctl, in a chroot),
        # then disable rescue and boot NixOS again. Needs the window open.
        packages.host-rescue = pkgs.writeShellApplication {
          name = "host-rescue";
          runtimeInputs = [
            config.packages.pass-cli
            pkgs.openssh
            pkgs.curl
            pkgs.jq
            pkgs.coreutils
          ];
          text = ''
            ip=''${1:?usage: host-rescue <ipv4> [read|reset-session]}
            action=''${2:-read}
            export PROTON_PASS_KEY_PROVIDER=''${PROTON_PASS_KEY_PROVIDER:-fs}
            export PROTON_PASS_AGENT_REASON="host-rescue: read jingzo-host's journal from rescue"
            umask 077
            key=$(mktemp)
            trap 'rm -f "$key"' EXIT
            pass-cli item view --vault-name ${vault} --item-title ${item} --field private_key >"$key"
            token=$(pass-cli item view --vault-name ${vault} --item-title hetzner-console --field Secret)
            api() { curl -fsS -X "$1" -H "Authorization: Bearer $token" -H "Content-Type: application/json" "https://api.hetzner.cloud/v1$2" ''${3:+-d "$3"}; }
            id=$(api GET "/servers?name=jingzo-host" | jq -r '.servers[0].id')
            keyid=$(api GET "/ssh_keys?name=jingzo-host-install" | jq -r '.ssh_keys[0].id')
            ssh_() { ssh -i "$key" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 "root@$ip" "$@"; }
            back() {
              api POST "/servers/$id/actions/disable_rescue" >/dev/null || true
              api POST "/servers/$id/actions/reset" >/dev/null || true
              echo "host-rescue: rescue disabled, booting NixOS again"
            }
            api POST "/servers/$id/actions/enable_rescue" "{\"type\":\"linux64\",\"ssh_keys\":[$keyid]}" >/dev/null
            api POST "/servers/$id/actions/reset" >/dev/null
            trap 'back; rm -f "$key"' EXIT
            echo "host-rescue: waiting for the rescue system"
            for _ in $(seq 1 60); do ssh_ true 2>/dev/null && break; sleep 10; done
            # shellcheck disable=SC2016
            ssh_ ACTION="$action" bash -s <<'REMOTE'
            set -x
            lsblk -o NAME,SIZE,FSTYPE,LABEL,MOUNTPOINT
            root=$(lsblk -lnpo NAME,FSTYPE /dev/sda | awk '$2 == "ext4" {print $1}' | head -1)
            mount "$root" /mnt
            ls -la /mnt/var/lib/kagamizo /mnt/var/lib 2>&1 | head -30
            for d in proc sys dev; do mount --bind /$d /mnt/$d; done
            jc() { chroot /mnt /nix/var/nix/profiles/system/sw/bin/journalctl -D /var/log/journal --no-pager "$@"; }
            jc --list-boots | tail -5
            last=$(jc --list-boots -q | tail -1 | awk '{print $2}')
            jc -b "$last" -u migration-staging -o short-iso | head -40
            jc -b "$last" -u host-report -o short-iso | head -40
            jc -b "$last" -u systemd-networkd -u systemd-networkd-wait-online -u systemd-resolved -o short-iso | tail -40
            jc -b "$last" -p err -o short-iso | tail -40
            # A stale pass-cli session keeps old permissions: the next boot
            # signs in fresh.
            if [ "$ACTION" = reset-session ]; then rm -rf /mnt/root/.local/share/proton-pass-cli; echo "pass-cli session removed"; fi
            REMOTE
          '';
        };

        packages.host-install = pkgs.writeShellApplication {
          name = "host-install";
          runtimeInputs = [
            pkgs.nixos-anywhere
            config.packages.pass-cli
            pkgs.jq
            pkgs.coreutils
          ];
          text = ''
            ip=''${1:?usage: host-install <ipv4>}
            export PROTON_PASS_KEY_PROVIDER=''${PROTON_PASS_KEY_PROVIDER:-fs}
            umask 077
            key=$(mktemp)
            # From Proton Pass into the file; never onto the screen.
            # An agent's pass-cli states why it reads (pass-cli 2.4.2 refuses otherwise).
            PROTON_PASS_AGENT_REASON="host-install: nixos-anywhere installs jingzo-host at $ip" \
              pass-cli item view --vault-name ${vault} --item-title ${item} --field private_key >"$key"
            [ -s "$key" ] || { echo "host-install: no install key in ${vault}/${item}" >&2; exit 1; }
            # What the installed host holds from the start (./credentials.nix,
            # to = "install"): written into the new root by nixos-anywhere.
            extra=$(mktemp -d)
            trap 'rm -f "$key"; rm -rf "$extra"' EXIT
            mkdir -p "$extra/var/lib/kagamizo"
            chmod 700 "$extra/var/lib/kagamizo"
            PROTON_PASS_AGENT_REASON="host-install: hand jingzo-host its Proton Pass token" \
              pass-cli item view --vault-name ${vault} --item-title host-token --output json |
              jq -j .item.content.note >"$extra/var/lib/kagamizo/host-token"
            [ -s "$extra/var/lib/kagamizo/host-token" ] || { echo "host-install: no host-token in ${vault}; run host-credentials sync" >&2; exit 1; }
            chmod 600 "$extra/var/lib/kagamizo/host-token"
            nixos-anywhere -L --flake "$(pwd)#jingzo-host" -i "$key" \
              --extra-files "$extra" --chown /var/lib/kagamizo 0:0 \
              --ssh-option StrictHostKeyChecking=accept-new "root@$ip"
          '';
        };
      };
  };
}
