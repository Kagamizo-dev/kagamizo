{ pkgs, ... }:
{
  networking.hostName = "rpi5";
  time.timeZone = "UTC";

  services.openssh.enable = true;
  services.openssh.settings.PasswordAuthentication = false;

  users.users.pi = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" ];
    openssh.authorizedKeys.keys = [
      # TODO: paste your SSH public key here
    ];
  };
  security.sudo.wheelNeedsPassword = false;

  networking.networkmanager.enable = true;

  environment.systemPackages = with pkgs; [ git vim htop ];

  system.stateVersion = "25.11";
}
