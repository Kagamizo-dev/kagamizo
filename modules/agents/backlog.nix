# The teams' backlog: work queued for each chartered team, typed, so the
# harness (`dispatch <team>/<topic> <brief>`, ../dsh/dispatch.nix) runs it
# when the team's key has credit. Each item names its team, the kind of
# work (a lifecycle in ./charters.nix, whose proposer must be that team),
# and its brief, a Markdown file in ./_backlog.
#
#   agents.backlog.<team>/<topic> = { kind; brief; status; }
{ lib, config, ... }:
let
  inherit (lib) mkOption types;
  cfg = config.agents.backlog;
  lifecycle = config.agents.lifecycle;

  problems = lib.concatLists (
    lib.mapAttrsToList (
      id: i:
      let
        team = lib.head (lib.splitString "/" id);
      in
      lib.optional (!(config.agents.charters ? ${team})) "agents.backlog.${id}: ${team} has no charter"
      ++
        lib.optional (lifecycle.${i.kind}.proposer != team)
          "agents.backlog.${id}: ${team} does not propose ${i.kind} (its proposer is ${lifecycle.${i.kind}.proposer})"
    ) cfg
  );
in
{
  options.agents.backlog = mkOption {
    type = types.attrsOf (
      types.submodule {
        options = {
          kind = mkOption {
            type = types.enum (lib.attrNames lifecycle);
            description = "The kind of work, which decides who reviews it and whether the owner signs off.";
          };
          brief = mkOption {
            type = types.path;
            description = "The job's brief, handed to the harness as the task.";
          };
          status = mkOption {
            type = types.enum [
              "queued"
              "active"
              "done"
            ];
            default = "queued";
          };
        };
      }
    );
    default = { };
    description = "Queued work per team, keyed team/topic.";
  };

  config = {
    governance.problems = problems;

    agents.backlog = {
      "twin/pumpkin-server" = {
        kind = "world";
        brief = ./_backlog/twin-pumpkin-server.md;
      };
      "twin/map-tiles" = {
        kind = "world";
        brief = ./_backlog/twin-map-tiles.md;
      };
      "builders/districts-and-rooms" = {
        kind = "world-content";
        brief = ./_backlog/builders-districts-and-rooms.md;
      };
      "twin/azalea-bots" = {
        kind = "world";
        brief = ./_backlog/twin-azalea-bots.md;
      };
      "upkeep/languages-burndown" = {
        kind = "code";
        brief = ./_backlog/upkeep-languages-burndown.md;
      };
    };
  };
}
