# The welcome screen the first terminal opens on: a system summary, a soft
# check and the keys. `welcome` shows it again.
{
  flake.nixosModules.welcome = ./_nixos.nix;
}
