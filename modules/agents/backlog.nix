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
      "upkeep/trading-public-rust" = {
        kind = "code";
        status = "done";
        brief = ./_backlog/upkeep-trading-public-rust.md;
      };
      "upkeep/trading-trade-rust" = {
        kind = "code";
        status = "done";
        brief = ./_backlog/upkeep-trading-trade-rust.md;
      };
      "reverse-engineering/nautilus-rust" = {
        kind = "reverse-engineering";
        status = "done";
        brief = ./_backlog/reverse-engineering-nautilus-rust.md;
      };
      "research-jingzo/trading-paper" = {
        kind = "strategy";
        status = "done";
        brief = ./_backlog/research-jingzo-trading-paper.md;
      };
      "upkeep/trading-nautilus-rust" = {
        kind = "code";
        brief = ./_backlog/upkeep-trading-nautilus-rust.md;
      };
      "upkeep/module-papers" = {
        kind = "code";
        brief = ./_backlog/upkeep-module-papers.md;
      };
      "upkeep/shell-web" = {
        kind = "code";
        status = "active";
        brief = ./_backlog/upkeep-shell-web.md;
      };
      "design/shell-input-and-targets" = {
        kind = "code";
        brief = ./_backlog/design-shell-input-and-targets.md;
      };
      "research-jingzo/weather-backtest" = {
        kind = "strategy";
        status = "active";
        brief = ./_backlog/research-jingzo-weather-backtest.md;
      };
      "research-jingzo/grounded-sources" = {
        kind = "strategy";
        brief = ./_backlog/research-jingzo-grounded-sources.md;
      };
      "upkeep/host-runner" = {
        kind = "code";
        status = "done";
        brief = ./_backlog/upkeep-host-runner.md;
      };
      "browser/engine-and-aliases" = {
        kind = "browser-flow";
        brief = ./_backlog/browser-engine-and-aliases.md;
      };
      "security/pipeline" = {
        kind = "security-check";
        brief = ./_backlog/security-pipeline.md;
      };
      "reverse-engineering/model-registry" = {
        kind = "reverse-engineering";
        brief = ./_backlog/reverse-engineering-model-registry.md;
      };
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
      "upkeep/account-links" = {
        kind = "code";
        brief = ./_backlog/upkeep-account-links.md;
      };
      "upkeep/matrix-bots" = {
        kind = "code";
        brief = ./_backlog/upkeep-matrix-bots.md;
      };
      "upkeep/openrouter-topup-flow" = {
        kind = "account-limit";
        brief = ./_backlog/upkeep-openrouter-topup-flow.md;
      };
      "design/account-dashboards" = {
        kind = "page";
        brief = ./_backlog/design-account-dashboards.md;
      };
      "design/project-board" = {
        kind = "page";
        brief = ./_backlog/design-project-board.md;
      };
      "design/settings-layout" = {
        kind = "page";
        brief = ./_backlog/design-settings-layout.md;
      };
      "upkeep/deterministic-legal-record" = {
        kind = "code";
        brief = ./_backlog/upkeep-deterministic-legal-record.md;
      };
      "upkeep/languages-burndown" = {
        kind = "code";
        brief = ./_backlog/upkeep-languages-burndown.md;
      };
    };
  };
}
