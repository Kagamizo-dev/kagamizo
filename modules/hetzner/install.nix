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
      # The first install ran on 2026-11-03 (host-install run 41568360740,
      # nixos-anywhere, 3 min). Open again, dated, for the reinstall that
      # hands the host its credentials (the owner's go, 2026-11-03); null
      # once it has run.
      window.until = "2026-11-04";
    };

    perSystem =
      { pkgs, config, ... }:
      {
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
