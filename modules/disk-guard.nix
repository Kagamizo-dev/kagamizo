# Internal-disk guard for the live USB: every non-USB disk (NVMe, SATA, internal
# SD) and its partitions is marked read-only at the block layer, so nothing in
# the session (a stray mount, an fsck, a `dd`) can modify the laptop's own drive
# (the Windows install included). USB devices, i.e. the stick we boot from and
# any other stick you plug in, are left alone.
#
# This protects against accidents, not against root deliberately running
# `blockdev --setrw`; the session has passwordless sudo by design.
{ pkgs, ... }:
let
  guard = pkgs.writeShellApplication {
    name = "internal-disk-guard";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.util-linux
    ];
    text = ''
      # The disk holding the live medium, if it is not on USB (e.g. an SD slot).
      boot_disk=""
      iso_src=$(findmnt -n -o SOURCE /iso 2>/dev/null || true)
      if [ -n "$iso_src" ]; then
        boot_disk=$(lsblk -no pkname "$iso_src" 2>/dev/null | head -n1 || true)
      fi

      guarded=0
      for sys in /sys/block/*; do
        name=$(basename "$sys")
        case "$name" in
          nvme* | sd* | mmcblk* | hd*) ;;
          *) continue ;;
        esac
        # Anything attached over USB is not an internal disk.
        case "$(readlink -f "$sys")" in
          */usb[0-9]*) echo "skip $name (USB)"; continue ;;
        esac
        if [ "$name" = "$boot_disk" ]; then
          echo "skip $name (live medium)"
          continue
        fi

        blockdev --setro "/dev/$name"
        for part in "$sys/$name"*; do
          [ -e "$part" ] || continue
          blockdev --setro "/dev/$(basename "$part")"
        done

        if [ "$(blockdev --getro "/dev/$name")" != "1" ]; then
          echo "FAILED to mark $name read-only" >&2
          exit 1
        fi
        echo "guarded $name (read-only)"
        guarded=$((guarded + 1))
      done
      echo "internal-disk-guard: $guarded internal disk(s) read-only"
    '';
  };
in
{
  # As each disk (or partition) appears, including ones that show up late.
  services.udev.extraRules = ''
    ACTION=="add|change", SUBSYSTEM=="block", KERNEL=="nvme[0-9]*|sd[a-z]*|mmcblk[0-9]*|hd[a-z]*", SUBSYSTEMS!="usb", RUN+="${pkgs.util-linux}/bin/blockdev --setro $devnode"
  '';

  # Early sweep, before anything could mount local filesystems; also logs the result.
  systemd.services.internal-disk-guard = {
    description = "Mark internal disks read-only";
    wantedBy = [ "sysinit.target" ];
    after = [ "systemd-udev-trigger.service" ];
    before = [
      "local-fs-pre.target"
      "sysinit.target"
    ];
    unitConfig.DefaultDependencies = false;
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${guard}/bin/internal-disk-guard";
    };
  };

  environment.systemPackages = [ guard ];
}
