# DeepSeek Harness (dsh), the self-extending agent harness the plan of
# 2026-11-04 adopts: MIT, a plugin runtime (Cordis) whose own plugins its
# agents may edit, a web UI, agent teams and subagents. Developer preview
# with breaking changes, so it is pinned exactly: the published package
# `@deepseek-ai/dsh` (a thin entry point over 86 of its own packages, no
# install scripts) by the lockfile ./_pin/package-lock.json and its hash,
# on Node 24. Upgrading is a pull request that passes the checks: a new
# version in ./_pin/package.json, `nix run .#dsh-lock`, a new hash.
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
      packages.dsh = pkgs.writeShellApplication {
        name = "dsh";
        runtimeInputs = [ nodejs ];
        text = ''
          exec ${pinned}/lib/node_modules/dsh-pin/node_modules/.bin/dsh "$@"
        '';
      };

      packages.dsh-lock = pkgs.writeShellApplication {
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
}
