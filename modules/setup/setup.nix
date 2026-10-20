# The first-run setup wizard: internet, Proton Pass, Wi-Fi from Proton Pass,
# then the OpenRouter-backed coding agents. `setup` runs it again.
{
  flake.nixosModules.setup = ./_nixos.nix;
}
