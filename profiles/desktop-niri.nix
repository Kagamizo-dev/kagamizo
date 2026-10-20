# Headed desktop: greetd auto-login into niri, plain Firefox, a few Wayland basics.
# Intel graphics only; the Nvidia GPU is deliberately left unused.
{ pkgs, ... }:
{
  programs.niri = {
    enable = true;
    useNautilus = false; # keeps the image smaller
  };

  # niri panics with "couldn't find a GPU" if the graphics device shows up after login,
  # so wait (up to 30 s) for it before greetd starts the session. Instant on real hardware.
  systemd.services.greetd = {
    path = [ pkgs.coreutils ];
    preStart = ''
      for _ in $(seq 30); do
        if ls /dev/dri/card* > /dev/null 2>&1; then exit 0; fi
        sleep 1
      done
    '';
  };

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

  environment = {
    etc = {
      "niri/config.kdl".source = ./niri/config.kdl;
      "wallpaper.png".source = ./wallpaper/japan-countryside-4k.png;
      "waybar/config.json".source = ./waybar/config.json;
      "waybar/style.css".source = ./waybar/style.css;
    };
    systemPackages = with pkgs; [
      foot # terminal
      fuzzel # launcher
      waybar # status bar
      swaybg # wallpaper
      wl-clipboard
      brightnessctl
    ];
  };

  fonts.packages = with pkgs; [
    dejavu_fonts
    font-awesome # waybar icons
    nerd-fonts.symbols-only # icons in the welcome screen
  ];

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
  };
  hardware.graphics.enable = true;
  networking.networkmanager.enable = true; # `nmtui` for Wi-Fi
}
