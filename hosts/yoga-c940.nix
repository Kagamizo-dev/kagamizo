# Lenovo Yoga C940 as an ephemeral live USB: root filesystem in RAM, the stick
# is only read from. The internal disk (and its Windows partition) is never touched.
{
  lib,
  pkgs,
  modulesPath,
  ...
}:
{
  imports = [
    (modulesPath + "/installer/cd-dvd/iso-image.nix")
    ../modules/tools.nix
    ../modules/tmux.nix
    ../modules/desktop-niri.nix
    ../modules/disk-guard.nix
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

  # Intel Wi-Fi/Bluetooth firmware and Sound Open Firmware for the speakers/mic.
  hardware = {
    enableRedistributableFirmware = true;
    firmware = [ pkgs.sof-firmware ];
    bluetooth.enable = true;
  };

  # Leave the Nvidia GPU (if this model has one) off; no driver headaches.
  boot.blacklistedKernelModules = [
    "nouveau"
    "nvidia"
    "nvidia_drm"
    "nvidia_modeset"
  ];
  # Mirror the console to the serial port too, so CI can watch the boot.
  boot.kernelParams = [
    "console=tty0"
    "console=ttyS0,115200"
  ];

  system.stateVersion = "26.05";
}
