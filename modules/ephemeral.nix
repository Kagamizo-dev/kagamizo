# Amnesic appliance: the whole root filesystem lives in RAM and the SD card is
# only used as a read-only source for /nix/store (same idea as the NixOS live
# ISO). Nothing is written to the card, so powering off = clean slate.
{ lib, ... }:
{
  fileSystems = {
    "/" = lib.mkForce {
      device = "none";
      fsType = "tmpfs";
      options = [
        "mode=0755"
        "size=75%"
      ];
    };

    # The SD card's root partition, mounted read-only (it holds /nix/store).
    "/nix/.ro-root" = {
      device = "/dev/disk/by-label/NIXOS_SD";
      fsType = "ext4";
      options = [
        "ro"
        "noatime"
      ];
      neededForBoot = true;
    };

    "/nix/.rw-store" = {
      device = "none";
      fsType = "tmpfs";
      options = [
        "mode=0755"
        "size=1G"
      ];
      neededForBoot = true;
    };

    # Store = read-only card contents + a RAM-backed layer for anything created
    # during the session.
    "/nix/store" = {
      overlay = {
        lowerdir = [ "/nix/.ro-root/nix/store" ];
        upperdir = "/nix/.rw-store/store";
        workdir = "/nix/.rw-store/work";
      };
      neededForBoot = true;
    };
  };

  # Root is not a partition any more, so skip the grow-the-partition step.
  sdImage.expandOnBoot = false;

  services.journald.storage = "volatile";
}
