# DeepSeek Harness (dsh), the self-extending agent harness the plan of
# 2026-11-04 adopts: MIT, a plugin runtime (Cordis) whose own plugins its
# agents may edit, a web UI, agent teams and subagents. Developer preview
# with breaking changes, so it is pinned exactly: the published package
# `@deepseek-ai/dsh` (a thin entry point over 86 of its own packages, no
# install scripts) by the lockfile ./_pin/package-lock.json and its hash,
# on Node 24. Upgrading is a pull request that passes the checks: a new
# version in ./_pin/package.json, `nix run .#dsh-lock`, a new hash.
#
# It runs on Node's own official Linux build, pinned by its SHASUMS256
# entry, not nixpkgs' Node: dsh's native loader (node-addon-require-builtin)
# recognises V8's compiled getters only as the official build lays them
# out, and nixpkgs' Node, built otherwise, fails it ("x64 sysv getter is
# not a recognized this->field accessor", 2026-11-04). nixpkgs' Node still
# installs the packages, which needs no addon.
#
#   nix run .#dsh -- web --port 3080    the harness, as published
#   nix run .#dsh-lock                  regenerate the lockfile for the
#                                       version ./_pin/package.json names
#
# The host runs it behind Access at harness.<zone> (../hetzner/_harness.nix),
# with the capped chat-and-code key and the agents' GitHub App token.
{ lib, ... }:
let
  pin = lib.importJSON ./_pin/package.json;
  version = pin.dependencies."@deepseek-ai/dsh";
in
{
  perSystem =
    { pkgs, ... }:
    let
      nodejs = pkgs.nodejs_24;
      # https://nodejs.org/dist/v24.21.0/SHASUMS256.txt (2026-11-04).
      nodeOfficial = pkgs.stdenv.mkDerivation {
        pname = "nodejs-official";
        version = "24.21.0";
        src = pkgs.fetchurl {
          url = "https://nodejs.org/dist/v24.21.0/node-v24.21.0-linux-x64.tar.xz";
          hash = "sha256-/Y5Z1aURUQ9qKYr7VI8Yx9KxvkBNi0on2U++SfVsstY=";
        };
        nativeBuildInputs = [ pkgs.autoPatchelfHook ];
        buildInputs = [ pkgs.stdenv.cc.cc.lib ];
        installPhase = "mkdir -p $out; cp -r bin lib include share $out/";
        dontStrip = true;
      };
      pinned = pkgs.buildNpmPackage {
        pname = "dsh-pin";
        inherit version nodejs;
        src = ./_pin;
        npmDepsHash = "sha256-JnJ+athl/bIYu1r7Cu9dhEWtTUL1LHh/738sDOkO2Bo=";
        dontNpmBuild = true;
        npmFlags = [ "--ignore-scripts" ];
        meta = {
          description = "DeepSeek Harness ${version}, pinned";
          license = lib.licenses.mit;
        };
      };
    in
    {
      packages = {
        dsh = pkgs.writeShellApplication {
          name = "dsh";
          text = ''
            exec ${nodeOfficial}/bin/node ${pinned}/lib/node_modules/dsh-pin/node_modules/@deepseek-ai/dsh/lib/bin.js "$@"
          '';
        };
        nodejs-official = nodeOfficial;
        dsh-lock = pkgs.writeShellApplication {
          name = "dsh-lock";
          runtimeInputs = [
            nodejs
            pkgs.prefetch-npm-deps
            pkgs.coreutils
          ];
          text = ''
            cd modules/dsh/_pin
            npm install --package-lock-only --ignore-scripts --no-audit --no-fund
            echo "npmDepsHash for modules/dsh/default.nix:"
            prefetch-npm-deps package-lock.json
          '';
        };
      };
    };
}
