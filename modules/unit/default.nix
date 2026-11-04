# Units of work delegated to the agent teams: each a typed task for one
# agent, run by a small loop after mini-swe-agent's (one bash command per
# turn, in a throwaway checkout, a linear history, a patch at the end) on
# the agent's own OpenRouter key, under a hard cost cap.
#
#   unit.units.<id> = { owner; task; instruction; paths; maxSteps;
#                       maxCents; accept; reasoning; }
#       owner     the governance agent whose key and share pay for it
#       task      an agents.tasks kind: it fixes the tier, so the model
#       paths     what it may change; the runner refuses a patch touching
#                 anything else
#       maxCents  the most the run may spend, in US cents
#       accept    the flake checks the patch must pass before it is taken
#
#   nix run .#unit -- list | show <id> | bounds [--json]
#   nix run .#unit -- run <id>     in a repository checkout: runs the unit
#                                  under its owner's key profile, writes the
#                                  patch, prints the checks to run on it
#
# checks.unit-lean proves every unit's cap fits its owner's monthly share,
# and all of one owner's units together too, so delegating can never spend
# past what ../agents allots. Units are declared in ./units.nix (code: the
# owner approves what is delegated, since each one spends).
{ lib, config, ... }:
let
  inherit (lib) mkOption types;
  cfg = config.unit.units;
  agents = config.governance.agents;
  inherit (config.agents) tiers tasks;
  q = builtins.toJSON;

  unit = types.submodule {
    options = {
      owner = mkOption { type = types.enum (lib.attrNames agents); };
      task = mkOption { type = types.enum (lib.attrNames tasks); };
      instruction = mkOption { type = types.str; };
      paths = mkOption {
        type = types.nonEmptyListOf (types.strMatching "[A-Za-z0-9_./*-]+");
        description = "Paths (a trailing /** is a whole tree) the patch may touch.";
      };
      maxSteps = mkOption {
        type = types.ints.between 1 60;
        default = 20;
      };
      maxCents = mkOption { type = types.ints.positive; };
      accept = mkOption {
        type = types.listOf (types.strMatching "[a-z0-9-]+");
        default = [ ];
        description = "Flake checks (checks.x86_64-linux.<name>) the patch must pass.";
      };
      reasoning = mkOption {
        type = types.bool;
        default = false;
        description = "Let the model reason before it answers; off, flash answers at once and costs a tenth.";
      };
    };
  };

  keyOf = a: if a.key != null then a.key else "swarms-${a.serves}";
  tierOf = u: tiers.${tasks.${u.task}};
  render = lib.mapAttrs (
    _: u:
    let
      a = agents.${u.owner};
      k = config.openrouter.keys.${keyOf a};
      t = tierOf u;
    in
    {
      inherit (u)
        owner
        task
        instruction
        paths
        maxSteps
        maxCents
        accept
        reasoning
        ;
      inherit (t) model;
      tier = t.name;
      key = keyOf a;
      inherit (k) profile variable;
      shareCents = a.budgetUsdPerMonth * 100;
    }
  ) cfg;

  problems = lib.concatLists (
    lib.mapAttrsToList (
      id: u:
      lib.optional ((tierOf u).runs != "openrouter")
        "unit.units.${id}: task ${u.task} runs on the ${(tierOf u).name} tier, which is not an OpenRouter model; host tiers are not wired to units yet"
    ) cfg
  );

  owners = lib.unique (lib.mapAttrsToList (_: u: u.owner) cfg);
  lean = ''
    namespace Kagamizo.Unit

    def units : List Unit := [
    ${lib.concatStringsSep ",\n" (
      lib.mapAttrsToList (
        id: u:
        "  { id := ${q id}, owner := ${q u.owner}, maxCents := ${toString u.maxCents}, maxSteps := ${toString u.maxSteps} }"
      ) cfg
    )}
    ]

    def shares : List Share := [
    ${lib.concatMapStringsSep ",\n" (
      o: "  { owner := ${q o}, cents := ${toString (agents.${o}.budgetUsdPerMonth * 100)} }"
    ) owners}
    ]

    theorem declared_within : within shares units = true := by decide +kernel

    end Kagamizo.Unit
  '';
in
{
  options.unit.units = mkOption {
    type = types.attrsOf unit;
    default = { };
  };

  config.perSystem =
    { pkgs, config, ... }:
    let
      bin = pkgs.rustPlatform.buildRustPackage {
        pname = "unit";
        version = "0.1.0";
        src = ./_src;
        cargoLock.lockFile = ./_src/Cargo.lock;
        UNITS_JSON = pkgs.writeText "units.json" (q render);
        meta.mainProgram = "unit-bin";
      };
      spec = config.packages.secretspec-toml;
      # `run` resolves the owner's key profile itself: secretspec puts the
      # key in the environment of the runner and nowhere else.
      unitCli = pkgs.writeShellApplication {
        name = "unit";
        runtimeInputs = [
          bin
          pkgs.curl
          pkgs.git
          pkgs.jq
          pkgs.util-linux
          pkgs.coreutils
          config.packages.secretspec
          config.packages.pass-cli
        ];
        text = ''
          export PROTON_PASS_KEY_PROVIDER=''${PROTON_PASS_KEY_PROVIDER:-fs}
          if [ "''${1:-}" = run ]; then
            id=''${2:?usage: unit run <id>}
            profile=$(unit-bin show "$id" --json | jq -r .profile)
            exec secretspec run --file ${spec} --profile "$profile" \
              --reason "unit run $id (modules/unit)" -- unit-bin run "$id"
          fi
          exec unit-bin "$@"
        '';
      };
    in
    {
      packages.unit = unitCli;
      checks.unit-lean =
        assert lib.assertMsg (problems == [ ]) (lib.concatStringsSep "\n" problems);
        pkgs.runCommand "unit-lean"
          {
            nativeBuildInputs = [ pkgs.lean4 ];
            facts = lean;
            passAsFile = [ "facts" ];
          }
          ''
            cat ${./_lean/Unit.lean} "$factsPath" > Check.lean
            lean Check.lean
            touch $out
          '';
      checks.unit-tests = bin.overrideAttrs (_: {
        doCheck = true;
      });
    };
}
