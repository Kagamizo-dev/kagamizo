# The project as typed data, not documents (the owner's rule, 2026-11-04:
# no more markdown). Epics, the owner's decisions and the gaps live in
# ./_data/*.json, typed here, proven coherent in Lean, and served by the
# `project` CLI; the PM swarm (governance.teams.pm) keeps them current and
# the owner talks to it in #pm, not through files.
#
#   project.epics.<id>      = { title; serves; team; status; blockedOn;
#                               owner; etaHours; modules; }
#   project.decisions.<id>  = { asked; question; options; answer; decided; }
#   project.gaps.<id>       = { step; why; closesWith; }
#   project.next            the epics to work on now (read-only): approved
#                           or in progress, every blocker settled
#   project.markdown        ./markdown.nix: the markdown files still allowed
#
#   nix run .#project -- status | next | epic <id> | decisions [--open]
#                        | gaps | decide <id> <option> [--json]
#
# `decide` rewrites ./_data/decisions.json, which is agent-mergeable content
# (governance.changeClasses.content); owner steps are operations.humanSteps.
# checks.project-lean proves the plan coherent (./_lean/Project.lean);
# checks.project-tests runs the crate's tests; checks.project-data holds
# the data files canonical and `decide`'s writer to the same form;
# checks.no-markdown fails on any markdown file ./markdown.nix does not list.
{
  lib,
  config,
  self,
  ...
}:
let
  inherit (lib) mkOption types;
  cfg = config.project;
  q = builtins.toJSON;
  date = types.strMatching "[0-9]{4}-[0-9]{2}-[0-9]{2}";
  statuses = [
    "proposed"
    "approved"
    "in-progress"
    "blocked"
    "done"
    "paused"
  ];

  epic = types.submodule {
    options = {
      title = mkOption { type = types.str; };
      serves = mkOption { type = types.enum (lib.attrNames config.identity.checked.entities); };
      team = mkOption {
        type = types.nullOr (types.enum (lib.attrNames config.governance.teams));
        description = "The team that does it; null until one exists for it.";
      };
      status = mkOption { type = types.enum statuses; };
      blockedOn = mkOption {
        type = types.listOf types.str;
        description = "Epic or decision ids it waits on.";
      };
      owner = mkOption {
        type = types.listOf (types.enum (lib.attrNames config.operations.humanSteps));
        description = "What the owner does for it: only the typed human steps.";
      };
      etaHours = mkOption { type = types.ints.positive; };
      modules = mkOption {
        type = types.listOf (types.strMatching "modules/[a-z0-9_-]+(/[A-Za-z0-9_./-]+)?");
      };
    };
  };
  decision = types.submodule {
    options = {
      asked = mkOption { type = date; };
      question = mkOption { type = types.str; };
      options = mkOption { type = types.nonEmptyListOf (types.strMatching "[a-z0-9-]+"); };
      answer = mkOption { type = types.nullOr types.str; };
      decided = mkOption { type = types.nullOr date; };
    };
  };
  gap = types.submodule {
    options = {
      step = mkOption { type = types.str; };
      why = mkOption { type = types.str; };
      closesWith = mkOption { type = types.str; };
    };
  };

  settled =
    id:
    if cfg.epics ? ${id} then
      cfg.epics.${id}.status == "done"
    else
      (cfg.decisions.${id} or { answer = null; }).answer != null;

  problems = lib.concatLists (
    lib.mapAttrsToList (
      id: e:
      map (b: "project.epics.${id}: blockedOn ${b} is neither an epic nor a decision") (
        lib.filter (b: !(cfg.epics ? ${b} || cfg.decisions ? ${b})) e.blockedOn
      )
      ++
        lib.optional (e.status == "done" && !(lib.all settled e.blockedOn))
          "project.epics.${id}: done, but waits on ${
            lib.concatStringsSep ", " (lib.filter (b: !settled b) e.blockedOn)
          }"
      ++ lib.optional (
        e.status == "blocked" && lib.all settled e.blockedOn
      ) "project.epics.${id}: blocked, but every blocker is settled"
    ) cfg.epics
    ++ lib.concatLists (
      lib.mapAttrsToList (
        id: d:
        lib.optional (
          (d.answer == null) != (d.decided == null)
        ) "project.decisions.${id}: answer and decided are set together"
        ++ lib.optional (
          d.answer != null && !(lib.elem d.answer d.options)
        ) "project.decisions.${id}: ${d.answer} is not one of ${lib.concatStringsSep ", " d.options}"
      ) cfg.decisions
    )
    ++ lib.concatLists (
      lib.mapAttrsToList (
        id: g:
        lib.optional (
          !(cfg.epics ? ${g.closesWith})
        ) "project.gaps.${id}: closesWith ${g.closesWith} is not an epic"
        ++ lib.optional (
          (cfg.epics.${g.closesWith} or { status = ""; }).status == "done"
        ) "project.gaps.${id}: ${g.closesWith} is done, so the gap is closed: remove it"
      ) cfg.gaps
    )
  );

  next = lib.attrNames (
    lib.filterAttrs (
      _: e:
      lib.elem e.status [
        "approved"
        "in-progress"
      ]
      && lib.all settled e.blockedOn
    ) cfg.epics
  );

  ctor = s: "." + (if s == "in-progress" then "inProgress" else s);
  lean = ''
    namespace Kagamizo.Project

    def epics : List Epic := [
    ${lib.concatStringsSep ",\n" (
      lib.mapAttrsToList (
        id: e: "  { id := ${q id}, status := ${ctor e.status}, blockedOn := ${q e.blockedOn} }"
      ) cfg.epics
    )}
    ]

    def decisions : List Decision := [
    ${lib.concatStringsSep ",\n" (
      lib.mapAttrsToList (
        id: d:
        "  { id := ${q id}, answered := ${lib.boolToString (d.answer != null)}, valid := ${
            lib.boolToString (d.answer == null || lib.elem d.answer d.options)
          } }"
      ) cfg.decisions
    )}
    ]

    def gaps : List Gap := [
    ${lib.concatStringsSep ",\n" (
      lib.mapAttrsToList (id: g: "  { id := ${q id}, closesWith := ${q g.closesWith} }") cfg.gaps
    )}
    ]

    theorem declared_coherent : coherent epics decisions gaps = true := by decide +kernel

    end Kagamizo.Project
  '';

  strs = xs: "&[${lib.concatMapStringsSep ", " q xs}]";
  opt = v: if v == null then "None" else "Some(${q v})";
  rust = ''
    pub const EPICS: &[Epic] = &[
    ${
      lib.concatStrings (
        lib.mapAttrsToList (id: e: ''
          Epic { id: ${q id}, title: ${q e.title}, serves: ${q e.serves}, team: ${opt e.team}, status: ${q e.status}, blocked_on: ${strs e.blockedOn}, owner: ${strs e.owner}, eta_hours: ${toString e.etaHours}, modules: ${strs e.modules} },
        '') cfg.epics
      )
    }];

    pub const DECISIONS: &[Decision] = &[
    ${
      lib.concatStrings (
        lib.mapAttrsToList (id: d: ''
          Decision { id: ${q id}, asked: ${q d.asked}, question: ${q d.question}, options: ${strs d.options}, answer: ${opt d.answer}, decided: ${opt d.decided} },
        '') cfg.decisions
      )
    }];

    pub const GAPS: &[Gap] = &[
    ${
      lib.concatStrings (
        lib.mapAttrsToList (id: g: ''
          Gap { id: ${q id}, step: ${q g.step}, why: ${q g.why}, closes_with: ${q g.closesWith} },
        '') cfg.gaps
      )
    }];

    pub const HUMAN_STEPS: &[(&str, &str)] = &[${
      lib.concatStringsSep ", " (
        lib.mapAttrsToList (n: why: "(${q n}, ${q why})") config.operations.humanSteps
      )
    }];
  '';
in
{
  options.project = {
    epics = mkOption { type = types.attrsOf epic; };
    decisions = mkOption { type = types.attrsOf decision; };
    gaps = mkOption { type = types.attrsOf gap; };
    next = mkOption {
      type = types.listOf types.str;
      readOnly = true;
      description = "Approved or in-progress epics whose blockers are all settled.";
    };
  };

  config = {
    project = {
      epics = lib.importJSON ./_data/epics.json;
      decisions = lib.importJSON ./_data/decisions.json;
      gaps = lib.importJSON ./_data/gaps.json;
      inherit next;
    };

    perSystem =
      { pkgs, ... }:
      let
        facts = pkgs.writeText "project-facts.rs" rust;
        project = pkgs.rustPlatform.buildRustPackage {
          pname = "project";
          version = "0.1.0";
          src = ./_src;
          cargoLock.lockFile = ./_src/Cargo.lock;
          PROJECT_FACTS = facts;
          meta.mainProgram = "project";
        };
        allowed = pkgs.writeText "markdown-allowed" (lib.concatLines (lib.attrNames cfg.markdown));
        # Every markdown file under a tree, minus the allowed ones.
        unlisted = pkgs.writeShellScript "markdown-unlisted" ''
          cd "$1"
          ${pkgs.findutils}/bin/find . -name '*.md' -not -path './.git/*' -printf '%P\n' |
            ${pkgs.coreutils}/bin/sort | ${pkgs.coreutils}/bin/comm -23 - <(${pkgs.coreutils}/bin/sort ${allowed})
        '';
      in
      {
        packages.project = project;
        checks = {
          project-lean =
            assert lib.assertMsg (problems == [ ]) (lib.concatStringsSep "\n" problems);
            pkgs.runCommand "project-lean"
              {
                nativeBuildInputs = [ pkgs.lean4 ];
                facts = lean;
                passAsFile = [ "facts" ];
              }
              ''
                cat ${./_lean/Project.lean} "$factsPath" > Check.lean
                lean Check.lean
                touch $out
              '';
          project-tests = project.overrideAttrs (_: {
            doCheck = true;
          });
          # The data stays in jq's canonical form, and `decide` writes that form.
          project-data =
            pkgs.runCommand "project-data"
              {
                nativeBuildInputs = [
                  pkgs.jq
                  project
                ];
              }
              ''
                for f in ${./_data}/*.json; do
                  jq -S --indent 2 . "$f" | diff -u - "$f" || {
                    echo "$f is not canonical: jq -S --indent 2" >&2
                    exit 1
                  }
                done
                project render decisions | diff -u - ${./_data/decisions.json}
                touch $out
              '';
          # No markdown but what ./markdown.nix lists; a new file fails, and
          # the check itself is tested on a stand-in tree.
          no-markdown = pkgs.runCommand "no-markdown" { } ''
            extra=$(${unlisted} ${self})
            if [ -n "$extra" ]; then
              echo "markdown files not in modules/project/markdown.nix (the no-markdown rule):" >&2
              echo "$extra" >&2
              exit 1
            fi
            mkdir -p stand-in/modules/x
            touch stand-in/CLAUDE.md stand-in/modules/x/notes.md
            [ "$(${unlisted} stand-in)" = "modules/x/notes.md" ]
            touch $out
          '';
        };
      };
  };
}
