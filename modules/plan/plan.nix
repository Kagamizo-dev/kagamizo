# The plan: the one source of truth for what is built, in what order, by
# which team, and what waits on the owner (the owner's direction of
# 2026-11-07: one planning app, the authority for tracking and plans).
# HANDOFF.md records sessions; this module holds the plan. The teams'
# backlog (../agents/backlog.nix) is the dispatchable part of it: every
# brief there belongs to one item here.
#
#   plan.goals.<g>      what the owner is after
#   plan.tracks.<t>     a stream of work, one per app and its team
#   plan.items.<id>     a piece of work: its track and place in it, status,
#                       what blocks it, what it depends on, its brief
#   plan.decisions.<d>  a question only the owner answers, open or decided
#
#   packages.plan       the plan as Markdown, generated
#   checks.plan         Lean (./_lean/Plan.lean): the plan is coherent
{ lib, config, ... }:
let
  inherit (lib) mkOption types;
  top = config;
  cfg = config.plan;
  q = builtins.toJSON;
  teams = lib.attrNames config.agents.charters;

  goal = types.submodule {
    options = {
      title = mkOption { type = types.str; };
      why = mkOption { type = types.str; };
    };
  };

  track = types.submodule {
    options = {
      title = mkOption { type = types.str; };
      goal = mkOption { type = types.enum (lib.attrNames cfg.goals); };
      team = mkOption {
        type = types.enum teams;
        description = "The team that owns the track today.";
      };
    };
  };

  item = types.submodule {
    options = {
      title = mkOption { type = types.str; };
      track = mkOption { type = types.enum (lib.attrNames cfg.tracks); };
      order = mkOption {
        type = types.ints.unsigned;
        description = "Its place in the track: lower first.";
      };
      status = mkOption {
        type = types.enum [
          "queued"
          "active"
          "done"
        ];
        default = "queued";
      };
      blocked = mkOption {
        type = types.enum [
          "none"
          "owner-decision"
          "owner-action"
          "credit"
          "hardware"
          "upstream"
        ];
        default = "none";
      };
      decision = mkOption {
        type = types.nullOr (types.enum (lib.attrNames cfg.decisions));
        default = null;
      };
      dependsOn = mkOption {
        type = types.listOf types.str;
        default = [ ];
      };
      backlog = mkOption {
        type = types.nullOr (types.enum (lib.attrNames config.agents.backlog));
        default = null;
        description = "The team's brief, when the item is dispatchable.";
      };
      source = mkOption {
        type = types.str;
        default = "";
        description = "Where it was first planned.";
      };
    };
  };

  decision = types.submodule {
    options = {
      question = mkOption { type = types.str; };
      recommended = mkOption {
        type = types.str;
        default = "";
      };
      answer = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "The owner's answer, dated; null while open.";
      };
    };
  };

  camel =
    s:
    let
      parts = lib.splitString "-" s;
    in
    lib.head parts
    + lib.concatMapStrings (p: lib.toUpper (lib.substring 0 1 p) + lib.substring 1 (-1) p) (
      lib.tail parts
    );

  byTrack =
    t:
    lib.sort (a: b: a.order < b.order) (
      lib.mapAttrsToList (id: i: i // { inherit id; }) (lib.filterAttrs (_: i: i.track == t) cfg.items)
    );
  mark =
    i:
    if i.status == "done" then
      "done"
    else if i.blocked != "none" then
      "blocked: ${i.blocked}${lib.optionalString (i.decision != null) " (${i.decision})"}"
    else
      i.status;

  markdown = lib.concatStringsSep "\n" (
    [
      "# The Kagamizo plan"
      ""
      "Generated from modules/plan; edit it there. Every item: track, order, status."
      ""
      "## Goals"
      ""
    ]
    ++ lib.mapAttrsToList (n: g: "- **${g.title}** (${n}): ${g.why}") cfg.goals
    ++ [
      ""
      "## Decisions waiting on the owner"
      ""
    ]
    ++ lib.mapAttrsToList (
      n: d:
      "- **${n}**: ${d.question}${
        lib.optionalString (d.recommended != "") " Recommended: ${d.recommended}"
      }"
    ) (lib.filterAttrs (_: d: d.answer == null) cfg.decisions)
    ++ [
      ""
      "## Decided"
      ""
    ]
    ++ lib.mapAttrsToList (n: d: "- **${n}**: ${d.question} ${d.answer}") (
      lib.filterAttrs (_: d: d.answer != null) cfg.decisions
    )
    ++ lib.concatLists (
      lib.mapAttrsToList (
        t: tr:
        [
          ""
          "## ${tr.title} (${t}; ${tr.team}; goal ${tr.goal})"
          ""
        ]
        ++ map (
          i:
          "${toString i.order}. **${i.title}** [${mark i}]${
            lib.optionalString (i.backlog != null) " brief: ${i.backlog}"
          }${lib.optionalString (i.dependsOn != [ ]) " after: ${lib.concatStringsSep ", " i.dependsOn}"}"
        ) (byTrack t)
      ) cfg.tracks
    )
  );
in
{
  options.plan = {
    goals = mkOption {
      type = types.attrsOf goal;
      default = { };
    };
    tracks = mkOption {
      type = types.attrsOf track;
      default = { };
    };
    items = mkOption {
      type = types.attrsOf item;
      default = { };
    };
    decisions = mkOption {
      type = types.attrsOf decision;
      default = { };
    };
  };

  config = {
    # The Plan card, opening the module's page with every track's items.
    shell.apps.plan = {
      name = "Plan";
      category = "work";
      kind = "module";
      module = "plan";
      description = "The one plan: goals, tracks, every item and what waits on you";
      view = [
        {
          title = "Waiting on you";
          rows = lib.mapAttrsToList (n: d: {
            title = n;
            detail = d.question;
          }) (lib.filterAttrs (_: d: d.answer == null) cfg.decisions);
        }
      ]
      ++ lib.mapAttrsToList (t: tr: {
        inherit (tr) title;
        rows = map (i: {
          title = "${toString i.order}. ${i.title}";
          detail = mark i;
        }) (byTrack t);
      }) cfg.tracks;
    };

    perSystem =
      { pkgs, config, ... }:
      {
        packages.plan = pkgs.writeText "PLAN.md" markdown;
        checks.plan = config.kagamizo.leanCheck {
          name = "plan";
          source = ./_lean/Plan.lean;
          facts = ''

            namespace Kagamizo.Plan
            def tracks : List String := ${q (lib.attrNames cfg.tracks)}
            def decisions : List Decision := [${
              lib.concatStringsSep ", " (
                lib.mapAttrsToList (
                  n: d: "{ id := ${q n}, isOpen := ${lib.boolToString (d.answer == null)} }"
                ) cfg.decisions
              )
            }]
            def items : List Item := [${
              lib.concatStringsSep ",\n  " (
                lib.mapAttrsToList (
                  n: i:
                  "{ id := ${q n}, track := ${q i.track}, status := .${i.status}, blocked := .${camel i.blocked}, decision := ${
                    q (if i.decision == null then "" else i.decision)
                  }, deps := ${q i.dependsOn}, backlog := ${q (if i.backlog == null then "" else i.backlog)} }"
                ) cfg.items
              )
            }]
            def backlog : List String := ${q (lib.attrNames top.agents.backlog)}

            set_option maxRecDepth 100000
            theorem plan_sound : sound tracks decisions items backlog = true := by decide +kernel
            end Kagamizo.Plan
          '';
        };
      };
  };
}
