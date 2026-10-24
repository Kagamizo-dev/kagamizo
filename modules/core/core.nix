# Flake-wide plumbing. Tools and checks run on x86_64-linux (CI and cloud
# sessions); the Pi images are aarch64 and declared in ../rpi5.
{ inputs, ... }:
{
  systems = [ "x86_64-linux" ];

  perSystem =
    { system, pkgs, ... }:
    {
      _module.args.pkgs = import inputs.nixpkgs { inherit system; };
      formatter = pkgs.nixfmt;
    };
}
