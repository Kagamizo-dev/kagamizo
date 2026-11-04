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
        # The login waits 2 minutes for its callback, too short for approving
        # on a phone and handing the address back (`mercury-session
        # callback`); wait 10, as `northwest login` does.
        postPatch = ''
          substituteInPlace internal/auth/oauth.go \
            --replace-fail 'context.WithTimeout(ctx, 2*time.Minute)' 'context.WithTimeout(ctx, 10*time.Minute)'
        '';
        nativeBuildInputs = [ pkgs.makeWrapper ];
        postInstall = ''
          wrapProgram $out/bin/mercury --set MERCURY_NO_UPDATE_CHECK 1
        '';
        meta.mainProgram = "mercury";
      };
    };
}
