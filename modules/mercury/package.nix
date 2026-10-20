# Mercury's official CLI, built from its pinned release source (flake input
# mercury-cli) with this flake's nixpkgs. The update notice is off: versions
# move only when the input does.
{ inputs, ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      packages.mercury = pkgs.buildGoModule {
        pname = "mercury";
        version = "0.11.8";
        src = inputs.mercury-cli;
        # From the release's own flake.nix; changes with go.sum.
        vendorHash = "sha256-Qt4hXbcjuaGyg18JCyEXXDXL9i1uVQFM8fDYyurjUBA=";
        subPackages = [ "cmd/mercury" ];
        env.CGO_ENABLED = "0";
        ldflags = [
          "-s"
          "-w"
          "-X main.version=0.11.8"
        ];
        nativeBuildInputs = [ pkgs.makeWrapper ];
        postInstall = ''
          wrapProgram $out/bin/mercury --set MERCURY_NO_UPDATE_CHECK 1
        '';
        meta.mainProgram = "mercury";
      };
    };
}
