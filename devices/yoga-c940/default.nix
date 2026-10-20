# Lenovo Yoga C940-14IIL (Intel Ice Lake, Iris Plus graphics, Intel AX201 Wi-Fi 6 +
# Bluetooth) as an ephemeral live USB: root filesystem in RAM, the stick is only
# read from. The internal disk (and its Windows partition) is never touched.
{
  lib,
  pkgs,
  modulesPath,
  ...
}:
let
  # Only the firmware this laptop needs. The full linux-firmware package is ~770 MB
  # of already-compressed files, which alone would push the ISO past GitHub's 2 GB
  # release-asset limit.
  #   iwlwifi-Qu*, -cc-*, -so-a0-hr*   Intel AX201 Wi-Fi (CNVi) families; the full
  #                  iwlwifi set for every Intel generation is ~290 MB
  #   intel/ibt-*    Intel Bluetooth
  #   i915/*         Ice Lake graphics: DMC, GuC and HuC
  #   regulatory.db* wireless regulatory database
  firmware = pkgs.runCommand "yoga-c940-firmware" { nativeBuildInputs = [ pkgs.findutils ]; } ''
    mkdir -p $out/lib/firmware
    cd ${pkgs.linux-firmware}/lib/firmware
    find . \( \
        -path './iwlwifi-Qu*' -o -path './iwlwifi-cc-*' -o -path './iwlwifi-so-a0-hr*' \
        -o -path './intel/iwlwifi/iwlwifi-Qu*' -o -path './intel/iwlwifi/iwlwifi-cc-*' \
        -o -path './intel/iwlwifi/iwlwifi-so-a0-hr*' \
        -o -path './intel/ibt-*' -o -path './i915/*' -o -name 'regulatory.db*' \) \
      \( -type f -o -type l \) -print0 |
      while IFS= read -r -d "" f; do
        mkdir -p "$out/lib/firmware/$(dirname "$f")"
        cp -P --no-preserve=mode "$f" "$out/lib/firmware/$f"
      done

    # Fail the build rather than ship an image without Wi-Fi or graphics firmware,
    # or with aliases that point at files we left out.
    cd $out/lib/firmware
    ls iwlwifi-QuZ-a0-hr-b0-* > /dev/null
    ls intel/ibt-* > /dev/null
    ls i915/icl_* > /dev/null
    ls regulatory.db* > /dev/null
    if [ -n "$(find . -xtype l)" ]; then
      echo "dangling firmware symlinks:" >&2
      find . -xtype l >&2
      exit 1
    fi
  '';
in
{
  imports = [
    (modulesPath + "/installer/cd-dvd/iso-image.nix")
    ../../profiles/tools.nix
    ../../profiles/tmux.nix
    ../../profiles/desktop-niri.nix
    ../../profiles/welcome.nix
    ../../profiles/setup.nix
  ];

  nixpkgs.hostPlatform = "x86_64-linux";
  networking.hostName = "yoga";
  time.timeZone = "UTC";

  users.users.user = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "networkmanager"
      "video"
      "audio"
    ];
  };
  security.sudo.wheelNeedsPassword = false;

  isoImage = {
    edition = "yoga-c940";
    makeEfiBootable = true;
    makeUsbBootable = true;
    appendToMenuLabel = " Yoga C940 (ephemeral)";
  };
  image.baseName = lib.mkForce "yoga-c940-ephemeral";

  hardware = {
    firmware = [
      firmware
      pkgs.sof-firmware # Sound Open Firmware: Ice Lake speakers and microphones
    ];
    cpu.intel.updateMicrocode = true;
    bluetooth.enable = true;
  };

  # Keep the image small: nothing here needs speech synthesis (its voices alone
  # are ~650 MB), cellular modems, or a copy of the nixpkgs source tree.
  services.speechd.enable = lib.mkForce false;
  networking.modemmanager.enable = false;
  documentation.nixos.enable = false;
  nix.channel.enable = false;
  nixpkgs.flake = {
    setNixPath = false;
    setFlakeRegistry = false;
  };

  # Mirror the console to the serial port too, so CI can watch the boot.
  boot.kernelParams = [
    "console=tty0"
    "console=ttyS0,115200"
  ];

  system.stateVersion = "26.05";
}
