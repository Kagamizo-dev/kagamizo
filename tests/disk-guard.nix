# NixOS VM test for the internal-disk guard: the VM gets a fake internal NVMe
# disk and a fake USB stick. The NVMe disk must become read-only (writes fail);
# the USB stick must stay writable.
{
  name = "disk-guard";

  nodes.machine =
    { pkgs, ... }:
    let
      disk = pkgs.runCommand "fake-disk.img" { } "truncate -s 32M $out";
    in
    {
      imports = [ ../modules/disk-guard.nix ];
      environment.systemPackages = [
        pkgs.e2fsprogs
        pkgs.util-linux
      ];
      virtualisation.qemu.options = [
        "-drive if=none,id=nvm,file=${disk},format=raw,snapshot=on"
        "-device nvme,drive=nvm,serial=guardtest"
        "-device qemu-xhci"
        "-drive if=none,id=stick,file=${disk},format=raw,snapshot=on"
        "-device usb-storage,drive=stick"
      ];
    };

  testScript = ''
    machine.wait_for_unit("multi-user.target")
    machine.wait_for_unit("internal-disk-guard.service")
    # Devices appear asynchronously; let udev finish applying its rules first.
    machine.wait_until_succeeds("test -b /dev/nvme0n1 && test -b /dev/sda", timeout=300)
    machine.succeed("udevadm settle")

    with subtest("the guard service ran and guarded the NVMe disk"):
        journal = machine.succeed("journalctl -u internal-disk-guard.service --no-pager")
        assert "guarded nvme0n1" in journal, journal

    with subtest("internal NVMe disk is read-only and cannot be written"):
        assert machine.succeed("blockdev --getro /dev/nvme0n1").strip() == "1"
        machine.fail("mkfs.ext4 -F /dev/nvme0n1")
        machine.fail("dd if=/dev/zero of=/dev/nvme0n1 bs=1k count=4 oflag=direct")

    with subtest("USB stick is left alone and stays writable"):
        assert machine.succeed("blockdev --getro /dev/sda").strip() == "0"
        machine.succeed("mkfs.ext4 -F /dev/sda")
  '';
}
