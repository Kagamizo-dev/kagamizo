# The Kagamizo shell as a NixOS target's session (./shell.nix): greetd logs
# straight into niri with the shell's own config, and the shell is its first
# window. Imported by a target's configuration with the shell's package and
# the target's name.
{ shell, target }:
{ lib, ... }:
{
  environment = {
    systemPackages = [ shell ];
    sessionVariables.KAGAMIZO_TARGET = target;
    # The shell's session in place of the desktop's (../desktop): one app at
    # a time, each on its own workspace.
    etc."niri/config.kdl".source = lib.mkForce ./_assets/niri.kdl;
  };
}
