# Jingzo's host on Hetzner Cloud, declared whole: the one machine with a
# fixed address, where calls that need an allow-listed IP (Mercury's
# write-scoped token) run. The cloud session only declares and applies; the
# host builds itself from this repository.
#
#   nixosConfigurations.jingzo-host            the system: its disk (disko),
#                                              network, and the timer that
#                                              pulls and switches to its
#                                              declared configuration
#   nixosConfigurations.jingzo-host-installer  a NixOS kexec image that
#                                              partitions the disk as declared
#                                              and installs jingzo-host, then
#                                              reboots into it
#   packages.jingzo-host-installer             that image's tarball, with a
#                                              static kexec from the pinned
#                                              nixpkgs (Hetzner's Ubuntu has
#                                              none); its hash is what the
#                                              first boot checks (./infra.nix)
#
# No SSH server and no remote access, as for every image in the repo: the
# host changes when the repository does.
{
  lib,
  config,
  inputs,
  ...
}:
let
  inherit (lib) mkOption types;
  cfg = config.hetzner.host;

  # The disk Hetzner Cloud gives an x86 server (virtio-scsi, /dev/sda),
  # GPT with a BIOS boot partition and an ESP, so GRUB boots either way.
  disk = {
    disko.devices.disk.main = {
      type = "disk";
      device = "/dev/sda";
      content = {
        type = "gpt";
        partitions = {
          bios = {
            size = "1M";
            type = "EF02";
          };
          esp = {
            size = "512M";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
            };
          };
          root = {
            size = "100%";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/";
            };
          };
        };
      };
    };
  };

  host =
    { pkgs, modulesPath, ... }:
    {
      imports = [
        (modulesPath + "/profiles/qemu-guest.nix")
        inputs.disko.nixosModules.disko
        disk
      ];
      networking.hostName = cfg.name;
      boot.loader.grub = {
        efiSupport = true;
        efiInstallAsRemovable = true;
      };
      # Hetzner Cloud hands the IPv4 out by DHCP.
      networking.useNetworkd = true;
      systemd.network.networks."10-uplink" = {
        matchConfig.Name = "en*";
        networkConfig.DHCP = "ipv4";
      };
      services.openssh.enable = false;
      nix.settings.experimental-features = [
        "nix-command"
        "flakes"
      ];
      # The host follows the repository: on a timer it builds its declared
      # configuration and switches to it.
      system.autoUpgrade = {
        enable = true;
        flake = "${cfg.flake}#${cfg.name}";
        dates = cfg.upgradeAt;
        allowReboot = true;
      };
      environment.systemPackages = [ pkgs.git ];
      system.stateVersion = "26.05";
    };

  installer =
    { pkgs, modulesPath, ... }:
    let
      target = config.flake.nixosConfigurations.${cfg.name}.config;
    in
    {
      imports = [ (modulesPath + "/installer/netboot/netboot-minimal.nix") ];
      networking.hostName = "${cfg.name}-installer";
      # The declared disk is ext4 and vfat: no ZFS in the image.
      boot.supportedFilesystems.zfs = lib.mkForce false;
      nix.settings.experimental-features = [
        "nix-command"
        "flakes"
      ];
      # Partition as declared, install the declared system, reboot into it.
      systemd.services.install-host = {
        wantedBy = [ "multi-user.target" ];
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        path = [
          pkgs.nix
          pkgs.nixos-install-tools
          pkgs.git
          pkgs.util-linux
        ];
        serviceConfig = {
          Type = "oneshot";
          StandardOutput = "journal+console";
        };
        script = ''
          ${target.system.build.diskoScript}
          nixos-install --no-root-passwd --flake ${lib.escapeShellArg "${cfg.flake}#${cfg.name}"}
          systemctl reboot
        '';
      };
      system.stateVersion = "26.05";
    };
in
{
  options.hetzner.host = {
    name = mkOption {
      type = types.strMatching "[a-z][a-z0-9-]*";
      default = "jingzo-host";
    };
    flake = mkOption {
      type = types.strMatching "github:[A-Za-z0-9-]+/[A-Za-z0-9._-]+(/[A-Za-z0-9._/-]+)?";
      description = "The flake the host installs from and follows (a public GitHub ref).";
    };
    upgradeAt = mkOption {
      type = types.str;
      default = "*-*-* 04:40:00";
      description = "When the host pulls and switches (systemd calendar).";
    };
  };

  config = {
    hetzner.host.flake = "github:Kagamizo-dev/kagamizo/ccr-a3dc11d9-lh43d5";

    flake.nixosConfigurations = {
      ${cfg.name} = inputs.nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [ host ];
      };
      "${cfg.name}-installer" = inputs.nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [ installer ];
      };
    };

    perSystem =
      { pkgs, ... }:
      let
        built = config.flake.nixosConfigurations."${cfg.name}-installer".config.system.build;
      in
      {
        packages.jingzo-host-installer = pkgs.runCommand "jingzo-host-installer.tar" { } ''
          mkdir tree
          cp -L ${built.kexecTree}/* tree/
          cp ${pkgs.pkgsStatic.kexec-tools}/bin/kexec tree/kexec
          sed -i 's|^if ! kexec -v|PATH="$(dirname "$0"):$PATH"; if ! kexec -v|' tree/kexec-boot
          tar -C tree -cf $out .
        '';
        checks.jingzo-host = config.flake.nixosConfigurations.${cfg.name}.config.system.build.toplevel;
      };
  };
}
