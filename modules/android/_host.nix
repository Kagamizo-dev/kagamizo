# The phone's twin on jingzo-host (./default.nix): the declared emulator as
# one systemd service, headless, its adb and console on the loopback only
# (the emulator binds them there; no port is open). KVM when the host has
# it, the emulator's software mode otherwise; the AVD lives in the
# service's state directory and is rebuilt from the declaration when
# missing. android-twin-screen is on the path for the agents and the owner.
{
  twin, # packages.android-twin
  screen, # packages.android-twin-screen
}:
{ pkgs, ... }:
{
  # The SDK's licence and its packages, admitted by name (../hetzner/_agents.nix
  # holds the predicate).
  nixpkgs.config.android_sdk.accept_license = true;

  systemd.services.android-twin = {
    description = "The phone's twin: the declared Android emulator, headless";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    path = [ pkgs.coreutils ];
    environment = {
      ANDROID_USER_HOME = "/var/lib/android-twin";
      HOME = "/var/lib/android-twin";
    };
    serviceConfig = {
      DynamicUser = true;
      StateDirectory = "android-twin";
      WorkingDirectory = "/var/lib/android-twin";
      # /dev/kvm is root:kvm 0660; without it the wrapper runs the
      # emulator in software mode.
      SupplementaryGroups = [ "kvm" ];
      ExecStart = "${twin}/bin/android-twin";
      Restart = "on-failure";
      RestartSec = 30;
      # The emulator's guest memory (the declared ram) and its own.
      MemoryMax = "3G";
      Nice = 10;
      # A full boot in software mode is slow.
      TimeoutStartSec = "20min";
    };
  };

  environment.systemPackages = [ screen ];
}
