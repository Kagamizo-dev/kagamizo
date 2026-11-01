# Lean, the typing layer for every API the modules use.
#
# ./_lean/Api.lean is the one model: a command-line tool, an HTTP API and an
# OpenTofu provider are each operations taking typed inputs, and its
# theorems say what an accepted call guarantees. Every pinned catalog
# (../catalog/_json) is rendered into that model by ./_render/catalog.py
# and checked by Lean, its named types proven closed where it declares any;
# a catalog that brings a kind of input the model lacks fails the render.
#
# ./_lean/Governance.lean types every governed action (../governance): its
# effect, and the command it runs, which Lean checks is in its tool's pinned
# catalog; and every agent grant, which Lean checks never spends, destroys
# or signs in.
#
#   nix build .#lean-api-<catalog>   a catalog, as Lean
#   nix build .#lean-governance      the governed actions and grants, as Lean
{ lib, config, ... }:
let
  json = ../catalog/_json;
  catalogs = map (lib.removeSuffix ".json") (
    lib.attrNames (lib.filterAttrs (n: _: lib.hasSuffix ".json" n) (builtins.readDir json))
  );
  camel =
    s:
    let
      parts = lib.splitString "-" s;
    in
    lib.head parts
    + lib.concatMapStrings (p: lib.toUpper (lib.substring 0 1 p) + lib.substring 1 (-1) p) (
      lib.tail parts
    );
  q = builtins.toJSON;

  # What each governed action runs: a pinned tool's command, by catalog, or a
  # wrapper of ours.
  toolOf = {
    mercury-cli = "mercury";
    brokerage = "public";
  };
  # Words of ours on those programs, not the tool's: `brokerage summary`
  # runs two of Public's commands.
  ownWords = {
    brokerage = [ "summary" ];
  };
  runsLean =
    command:
    let
      words = lib.splitString " " command;
      program = lib.head words;
      op = lib.concatStringsSep " " (lib.tail words);
      api = toolOf.${program} or null;
    in
    if command == null then
      ''(.wrapper "mcp")''
    else if api != null && !(lib.elem op (ownWords.${program} or [ ])) then
      "(.command ${q api} ${q op})"
    else
      "(.wrapper ${q program})";

  actions = lib.concatLists (
    lib.mapAttrsToList (
      provider: as:
      lib.mapAttrsToList (
        name: a:
        "  { provider := ${q provider}, name := ${q name}, effect := .${camel a.effect}, runs := ${runsLean a.command} }"
      ) as
    ) config.governance.actions
  );
  grants = lib.concatLists (
    lib.mapAttrsToList (
      agent: a:
      map (
        g:
        "  { agent := ${q agent}, account := ${q g.account}, effects := [${
            lib.concatMapStringsSep ", " (e: ".${camel e}") g.effects
          }] }"
      ) a.grants
    ) config.governance.agents
  );
  governed = ''
    namespace Kagamizo.Governance
    open Kagamizo.Api

    /-- Every governed action, rendered by ../default.nix. -/
    def actions : List Action := [
    ${lib.concatStringsSep ",\n" actions}
    ]

    /-- Every agent grant, rendered by ../default.nix. -/
    def grants : List Grant := [
    ${lib.concatStringsSep ",\n" grants}
    ]

    /-- Every action that runs a pinned tool's command names one its catalog has. -/
    theorem actions_typed :
        actions.all (Action.typed [Mercury.api, Public.api]) = true := by decide +kernel

    /-- No agent is granted spending, destroying or signing in. -/
    theorem grants_allowed : grants.all Grant.allowed = true := by decide +kernel

    end Kagamizo.Governance
  '';
in
{
  perSystem =
    { pkgs, config, ... }:
    let
      python = "${pkgs.python3}/bin/python3 -I";
      # Each catalog's pinned version, as ../catalog/sources.nix reads it.
      versionOf =
        n: config.catalog.sources.${n}.version or (throw "lean: no pinned version known for catalog ${n}");
      render =
        n:
        pkgs.runCommand "${n}.lean" { } ''
          ${python} ${./_render/catalog.py} ${n} ${lib.escapeShellArg (versionOf n)} ${json}/${n}.json $out
        '';
      rendered = lib.genAttrs catalogs render;
      # The same model as JSON, for the Rust checker.
      model =
        n:
        pkgs.runCommand "${n}-model.json" { } ''
          ${python} ${./_render/catalog.py} ${n} ${lib.escapeShellArg (versionOf n)} ${json}/${n}.json \
            "$TMPDIR/model.lean" $out
        '';
      models = lib.genAttrs catalogs model;
      # `api-check MODEL.json WORDS...`: whether a command line is one the
      # pinned tool accepts, by the model Api.lean states (./_src).
      api-check = pkgs.rustPlatform.buildRustPackage {
        pname = "api-check";
        version = "0.1.0";
        src = ./_src;
        cargoLock.lockFile = ./_src/Cargo.lock;
        API_CHECK_PUBLIC = models.public;
        meta.mainProgram = "api-check";
      };
      leanCheck =
        name: files:
        pkgs.runCommand name { nativeBuildInputs = [ pkgs.lean4 ]; } ''
          cat ${lib.concatStringsSep " " files} > Check.lean
          lean Check.lean
          touch $out
        '';
      governedLean = pkgs.writeText "Governed.lean" governed;
    in
    {
      packages =
        lib.mapAttrs' (n: v: lib.nameValuePair "lean-api-${n}" v) rendered
        // lib.mapAttrs' (n: v: lib.nameValuePair "api-model-${n}" v) models
        // {
          lean-governance = governedLean;
          # The model itself, for a module's own Lean checks.
          lean-api-core = pkgs.writeText "Api.lean" (builtins.readFile ./_lean/Api.lean);
          inherit api-check;
        };
      checks =
        lib.mapAttrs' (
          n: v:
          lib.nameValuePair "lean-api-${n}" (
            leanCheck "lean-api-${n}" [
              ./_lean/Api.lean
              v
            ]
          )
        ) rendered
        // {
          lean-governance = leanCheck "lean-governance" [
            ./_lean/Api.lean
            rendered.mercury
            rendered.public
            ./_lean/Governance.lean
            governedLean
          ];
        };
    };
}
