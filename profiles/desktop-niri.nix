# Headed desktop: greetd auto-login into niri, plain Firefox, a few Wayland basics.
# Intel graphics only; the Nvidia GPU is deliberately left unused.
{ pkgs, ... }:
{
  programs.niri = {
    enable = true;
    useNautilus = false; # keeps the image smaller
  };
  environment.etc."niri/config.kdl".source = ./niri/config.kdl;

  # No password prompt: this is a live USB and nothing persists.
  services.greetd = {
    enable = true;
    settings = {
      initial_session = {
        command = "niri-session";
        user = "user";
      };
      default_session = {
        command = "${pkgs.tuigreet}/bin/tuigreet --time --cmd niri-session";
        user = "greeter";
      };
    };
  };

  programs.firefox = {
    enable = true;
    policies = {
      DisableTelemetry = true;
      DisableFirefoxStudies = true;
      DontCheckDefaultBrowser = true;
      OverrideFirstRunPage = "";
      NoDefaultBookmarks = true;
    };
  };

  environment.systemPackages = with pkgs; [
    foot # terminal
    fuzzel # launcher
    waybar # status bar
    wl-clipboard
    brightnessctl
  ];

  fonts.packages = with pkgs; [
    dejavu_fonts
    font-awesome # waybar icons
  ];

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
  };
  hardware.graphics.enable = true;
  networking.networkmanager.enable = true; # `nmtui` for Wi-Fi
}
