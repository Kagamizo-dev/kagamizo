{ pkgs, ... }:
{
  networking.hostName = "rpi5";
  time.timeZone = "UTC";

  # Appliance: log in at the keyboard/HDMI console, straight into tmux.
  # No network login of any kind (no SSH), no passwords to leak: this repo is public.
  users.users.pi = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "networkmanager"
    ];
  };
  security.sudo.wheelNeedsPassword = false;
  services.getty.autologinUser = "pi";
  programs.bash.loginShellInit = ''
    if [ -z "$TMUX" ] && [ "$(tty)" = /dev/tty1 ]; then
      exec tmux new-session -A -s main
    fi
  '';

  # Join Wi-Fi from the console with `nmtui`.
  networking.networkmanager.enable = true;

  environment.systemPackages = with pkgs; [
    git
    vim
    htop
    proton-pass-cli # `pass-cli login` prints a URL you can open on your phone
  ];

  system.stateVersion = "26.05";
}
