# The runner service on jingzo-host: a systemd unit that calls the Rust binary
# (./_runner) directly — never shell-in-Nix-strings — with the profiles and
# secrets it needs.  Also declares the research team's daily schedule as typed
# timers, each a typed item (team, topic, brief), never a shell script.
#
#   agents.runner = {
#     enable       = true;   # the systemd unit and the timers
#   }
#
# The periodics (timers for the research team's daily jobs):
#   agents.runner.scheduled = {
#     <name> = { team; topic; brief; calendar; };
#   }
#
# Every item: team is an agents.charters name, topic is a kebab-case slug,
# brief is a sentence of what the job does, and calendar is a systemd
# OnCalendar expression.
#
#   packages.agent-runner     the Rust binary (built in perSystem)
{ lib, config, ... }:
let
  inherit (lib) mkOption types;
  cfg = config.agents;
  charterNames = lib.attrNames cfg.charters;

  timerItem = types.submodule {
    options = {
      team = mkOption {
        type = types.enum charterNames;
        description = "The team that runs this job — one of agents.charters.";
      };
      topic = mkOption {
        type = types.strMatching "[a-z][a-z0-9-]*";
        description = "A kebab-case slug for the branch name agents/<team>/<topic>.";
      };
      brief = mkOption {
        type = types.str;
        description = "A one-line description of what the job does, passed as the brief.";
      };
      calendar = mkOption {
        type = types.str;
        description = "systemd OnCalendar expression (e.g. 'daily 06:00:00').";
      };
    };
  };

in
{
  options.agents.runner = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = "Enable the runner service and its timers on the host.";
    };
    requestFile = mkOption {
      type = types.str;
      default = ".github/agents.request";
      description = "The committed request file path, relative to the worktree root.";
    };
    scheduled = mkOption {
      type = types.attrsOf timerItem;
      default = { };
      description = "Scheduled jobs, each a typed item (team, topic, brief, calendar).";
    };
  };

  config = {
    # The research team's daily jobs (paper days, backtests), declared as typed
    # timers: each is a typed item (team, topic, brief, calendar), never a shell
    # script.  The timers produce a request file; the runner service reads it.
    agents.runner.scheduled = {
      # Daily weather backtest: before the market opens.
      "research-jingzo/daily-backtest-weather" = {
        team = "research-jingzo";
        topic = "daily-backtest-weather";
        brief = "Run the daily weather backtest against the NWS climate reports and Kalshi public data, update the backtest record.";
        calendar = "daily 05:00:00";
      };
      # Daily grounded sources refresh: update the source catalog with any
      # new API endpoints, check terms, record cadence.
      "research-jingzo/daily-sources-refresh" = {
        team = "research-jingzo";
        topic = "daily-sources-refresh";
        brief = "Daily refresh of grounded data sources: Open-Meteo, NWS, OpenSky, FIRMS, GOES. Check endpoints are live, update the catalog.";
        calendar = "daily 05:30:00";
      };
      # Paper days: the research team's daily research loop.
      "research-jingzo/paper-day" = {
        team = "research-jingzo";
        topic = "paper-day";
        brief = "A paper day: research a trading strategy and write it up as a dated paper. Use the Kalshi, weather, flight and satellite data from jingzo-host.";
        calendar = "daily 08:00:00";
      };
      # After-hours price analysis: look at the day's closes and update signal
      # records.
      "research-jingzo/daily-signals" = {
        team = "research-jingzo";
        topic = "daily-signals";
        brief = "Review the day's closes and produce signal records for open market contracts.";
        calendar = "daily 20:00:00";
      };
    };

    perSystem =
      { pkgs, ... }:
      {
        packages.agent-runner = pkgs.rustPlatform.buildRustPackage {
          pname = "agent-runner";
          version = "0.1.0";
          src = ./_runner;
          cargoLock.lockFile = ./_runner/Cargo.lock;
          meta.mainProgram = "agent-runner";
        };
      };
  };
}
