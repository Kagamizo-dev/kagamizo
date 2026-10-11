{ pkgs, ... }:
{
  networking.hostName = "rpi5";
  time.timeZone = "UTC";

  services.openssh.enable = true;
  services.openssh.settings.PasswordAuthentication = false;

  users.users.pi = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "networkmanager"
    ];
    openssh.authorizedKeys.keys = [
      # TODO: paste your SSH public key here, then delete initialPassword below
    ];
    # TEMPORARY, for keyboard/HDMI login only (SSH password login is disabled
    # above). This repo is public, so treat this password as known to everyone.
    initialPassword = "changeme";
  };
  security.sudo.wheelNeedsPassword = false;

  networking.networkmanager.enable = true;

  environment.systemPackages = with pkgs; [
    git
    vim
    htop
  ];

  system.stateVersion = "26.05";
}
