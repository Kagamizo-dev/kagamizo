# REA (Reverse Engineer Anything, github.com/morluto/rea), pinned at its
# rea-agents-6.7.0 tag and built from that source: the tool that maps what a
# site or app does where no API is published, so a browser flow is backed
# by a reverse-engineered model of the site rather than by guesses.
#
#   nix run .#rea -- <command>       its CLI (also its MCP server)
#   nix build .#rea-catalog          its tool catalog, generated from the
#                                    same source (docs/public/product-catalog.json)
#
# Install scripts are off: esbuild's Linux binary is a package of its own
# in the lockfile, frida is a development dependency, fsevents is macOS's.
{ inputs, ... }:
{
  perSystem =
    { pkgs, lib, ... }:
    let
      rea = pkgs.buildNpmPackage {
        pname = "rea-agents";
        version = "6.7.0";
        src = inputs.rea;
        nodejs = pkgs.nodejs_22;
        npmDepsHash = "sha256-BWMsF0ja+AyQg3w7BKVjzbI372HOKd2bFpFwbCAB5cA=";
        npmFlags = [ "--ignore-scripts" ];
        makeCacheWritable = true;
        buildPhase = ''
          runHook preBuild
          npm run compile
          node scripts/generate-product-catalog.mjs
          runHook postBuild
        '';
        installPhase = ''
          runHook preInstall
          mkdir -p $out/lib/rea $out/bin $out/share/rea
          cp -r . $out/lib/rea
          cp docs/public/product-catalog.json $out/share/rea/
          makeWrapper ${lib.getExe pkgs.nodejs_22} $out/bin/rea \
            --add-flags $out/lib/rea/scripts/rea.mjs
          runHook postInstall
        '';
        nativeBuildInputs = [ pkgs.makeWrapper ];
        meta.mainProgram = "rea";
      };
    in
    {
      packages = {
        inherit rea;
        rea-catalog = pkgs.runCommand "rea-catalog.json" { } ''
          cp ${rea}/share/rea/product-catalog.json $out
        '';
      };
    };
}
