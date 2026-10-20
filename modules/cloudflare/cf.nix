# Cloudflare's `cf` CLI, pinned by ./_cf/package-lock.json. It signs in with
# OAuth device authorization: it prints a link and a code, you approve them on
# your phone behind Cloudflare's 2FA, and the session it gets is the root
# credential. Nothing long-lived is ever created on the dashboard by hand.
{
  perSystem =
    { pkgs, ... }:
    {
      packages.cf = pkgs.buildNpmPackage {
        pname = "cf";
        version = "1.0.0-beta.13";
        src = ./_cf;
        nodejs = pkgs.nodejs_22;
        npmDepsHash = "sha256-aB2cs01SnwTVCCEmMhuKjOyJJACv/XXnCXHatqz+tCQ=";
        # Install the pinned tree as-is: no package scripts, nothing to build.
        npmFlags = [ "--ignore-scripts" ];
        dontNpmBuild = true;
        nativeBuildInputs = [ pkgs.makeWrapper ];
        installPhase = ''
          runHook preInstall
          mkdir -p $out/lib $out/bin
          cp -r node_modules $out/lib/
          makeWrapper ${pkgs.nodejs_22}/bin/node $out/bin/cf \
            --add-flags $out/lib/node_modules/cf/bin/cf \
            --set CLOUDFLARE_TELEMETRY_DISABLED 1
          runHook postInstall
        '';
      };
    };
}
