# Steam's tools on jingzo-host (./default.nix), only while the owner has
# enabled them: steamcmd (under steam-run, from nixpkgs) for testing and
# shipping builds. Off, this adds nothing, and the host evaluates unchanged;
# the unfree names it needs are admitted beside the Android SDK's
# (../hetzner/_agents.nix, alsoUnfree).
{ enable }:
{ lib, pkgs, ... }:
{
  environment.systemPackages = lib.optional enable pkgs.steamcmd;
}
