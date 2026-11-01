# CI, declared once and typed; a code host is only a runner.
#
#   ci.workflows.<w> = { description; on; jobs.<j> = { runner; steps; ... }; }
#
# Nothing in a host's own syntax is written by hand: each host is a renderer
# (./_hosts/github.nix, ./_hosts/forgejo.nix) from this one model, and
# `checks.ci-rendered` fails when a committed workflow file differs from what
# Nix renders (`nix run .#ci-render` writes them). Moving to another host
# is enabling its renderer. Steps are commands of this flake (`nix run`,
# `nix build`), so the work itself never depends on the host. Values only a
# host knows (the commit range of a push, the run's commit) are typed
# `ci.context` names that each renderer translates.
#
# ./_lean/Pipeline.lean is the model in Lean; `checks.ci-pipeline` proves
# every declared workflow's `needs` names declared jobs and has no cycle,
# and that no job a pull request can start holds a write permission.
#
# Migrated so far: checks, spec-drift. build-image, infra, yoga-c940 and
# github-bootstrap still live as hand-written YAML (HANDOFF.md).
{
  lib,
  config,
  self,
  ...
}:
let
  inherit (lib) mkOption types;
  cfg = config.ci;

  # What a host may be asked for at run time, by name.
  contexts = [
    "commit-range"
    "commit"
    "repository"
  ];
  value = types.either types.str (
    types.submodule {
      options.context = mkOption { type = types.enum contexts; };
    }
  );

  step = types.submodule {
    options = {
      name = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
      run = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "A shell command; keep it to this flake's commands.";
      };
      env = mkOption {
        type = types.attrsOf value;
        default = { };
      };
      always = mkOption {
        type = types.bool;
        default = false;
        description = "Run even when an earlier step failed.";
      };
      artifact = mkOption {
        type = types.nullOr (
          types.submodule {
            options = {
              name = mkOption { type = types.strMatching "[a-z0-9-]+"; };
              path = mkOption { type = types.str; };
            };
          }
        );
        default = null;
        description = "Keep these files with the run (screenshots, logs); not with `run`.";
      };
    };
  };

  job = types.submodule {
    options = {
      name = mkOption { type = types.str; };
      runner = mkOption {
        type = types.enum [
          "linux-x86_64"
          "linux-x86_64-kvm"
          "linux-aarch64"
        ];
        description = "What the job runs on; -kvm for NixOS VM tests.";
      };
      timeoutMinutes = mkOption { type = types.ints.between 1 360; };
      needs = mkOption {
        type = types.listOf types.str;
        default = [ ];
      };
      permissions = mkOption {
        type = types.attrsOf (
          types.enum [
            "read"
            "write"
          ]
        );
        default = {
          contents = "read";
        };
      };
      history = mkOption {
        type = types.enum [
          "tip"
          "full"
        ];
        default = "tip";
        description = "How much git history the checkout has.";
      };
      steps = mkOption { type = types.nonEmptyListOf step; };
    };
  };

  trigger = types.submodule {
    options = {
      push = mkOption {
        type = types.nullOr (
          types.submodule {
            options = {
              branches = mkOption {
                type = types.nullOr (types.listOf types.str);
                default = null;
              };
              branchesIgnore = mkOption {
                type = types.nullOr (types.listOf types.str);
                default = null;
              };
            };
          }
        );
        default = null;
      };
      pullRequest = mkOption {
        type = types.bool;
        default = false;
      };
      call = mkOption {
        type = types.bool;
        default = false;
        description = "Another workflow may run this one.";
      };
      manual = mkOption {
        type = types.bool;
        default = false;
      };
      schedule = mkOption {
        type = types.listOf (types.strMatching "[0-9*/,-]+ [0-9*/,-]+ [0-9*/,-]+ [0-9*/,-]+ [0-9*/,-]+");
        default = [ ];
      };
    };
  };

  workflow = types.submodule {
    options = {
      description = mkOption {
        type = types.str;
        description = "What the workflow is for; the comment atop each rendered file.";
      };
      on = mkOption { type = trigger; };
      cancelSuperseded = mkOption {
        type = types.bool;
        default = true;
        description = "A newer push to the same ref cancels this run.";
      };
      jobs = mkOption { type = types.attrsOf job; };
    };
  };

  # The model as Lean facts, for ./_lean/Pipeline.lean.
  q = builtins.toJSON;
  facts = ''
    namespace Kagamizo.Ci

    /-- Every declared workflow, rendered by ../default.nix. -/
    def declared : List Workflow := [
    ${lib.concatStringsSep ",\n" (
      lib.mapAttrsToList (w: wf: ''
        { name := ${q w}, pullRequest := ${lib.boolToString wf.on.pullRequest}, jobs := [
        ${lib.concatStringsSep ",\n" (
          lib.mapAttrsToList (
            j: jb:
            "    { name := ${q j}, needs := [${lib.concatMapStringsSep ", " q jb.needs}], writes := ${
                  lib.boolToString (lib.any (p: p == "write") (lib.attrValues jb.permissions))
                } }"
          ) wf.jobs
        )}
          ] }'') cfg.workflows
    )}
    ]

    theorem declared_sound : declared.all Workflow.sound = true := by decide

    end Kagamizo.Ci
  '';
in
{
  imports = [
    ./_hosts/github.nix
    ./_hosts/forgejo.nix
  ];

  options.ci = {
    contexts = mkOption {
      type = types.listOf types.str;
      readOnly = true;
      default = contexts;
    };
    workflows = mkOption {
      type = types.attrsOf workflow;
      default = { };
    };
    hosts = mkOption {
      type = types.attrsOf (
        types.submodule {
          options = {
            enable = mkOption {
              type = types.bool;
              default = false;
              description = "Whether this host's files are committed and checked.";
            };
            dir = mkOption {
              type = types.str;
              description = "Where its workflow files live, from the repository root.";
            };
            render = mkOption {
              type = types.functionTo (types.functionTo types.attrs);
              description = "pkgs -> { <file> = <derivation>; }: the host's files for every workflow.";
            };
          };
        }
      );
      default = { };
    };
  };

  config.perSystem =
    { pkgs, ... }:
    let
      enabled = lib.filterAttrs (_: h: h.enable) cfg.hosts;
      files = lib.mapAttrs (_: h: h.render pkgs cfg.workflows) cfg.hosts;
      tree = lib.concatLists (
        lib.mapAttrsToList (
          host: fs:
          lib.mapAttrsToList (f: drv: {
            name = "${cfg.hosts.${host}.dir}/${f}";
            path = drv;
          }) fs
        ) (lib.filterAttrs (n: _: enabled ? ${n}) files)
      );
      rendered = pkgs.linkFarm "ci-rendered" tree;
      # Every host renders, enabled or not: a model a host cannot express
      # fails here, before anyone moves to it.
      all = pkgs.linkFarm "ci-all-hosts" (
        lib.concatLists (
          lib.mapAttrsToList (
            host: fs:
            lib.mapAttrsToList (f: drv: {
              name = "${host}/${f}";
              path = drv;
            }) fs
          ) files
        )
      );
    in
    {
      packages = {
        ci-rendered = rendered;
        ci-all-hosts = all;
        ci-render = pkgs.writeShellApplication {
          name = "ci-render";
          runtimeInputs = [ pkgs.git ];
          text = ''
            cd "$(git rev-parse --show-toplevel)"
            ${lib.concatMapStrings (t: ''
              install -D -m 644 ${t.path} ${t.name}
            '') tree}
            git status --short ${lib.concatStringsSep " " (lib.mapAttrsToList (_: h: h.dir) enabled)}
          '';
        };
      };
      checks = {
        ci-rendered = pkgs.runCommand "ci-rendered" { } ''
          ${lib.concatMapStrings (t: ''
            if ! diff -q ${t.path} ${self}/${t.name} >/dev/null 2>&1; then
              echo "${t.name} is not what modules/ci renders: nix run .#ci-render" >&2
              exit 1
            fi
          '') tree}
          ls ${all} >/dev/null
          touch $out
        '';
        ci-pipeline = pkgs.runCommand "ci-pipeline" { nativeBuildInputs = [ pkgs.lean4 ]; } ''
          cat ${./_lean/Pipeline.lean} ${pkgs.writeText "Facts.lean" facts} > Check.lean
          lean Check.lean
          touch $out
        '';
      };
    };
}
