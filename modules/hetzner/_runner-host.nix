# The agent runner's systemd units and timers on jingzo-host: the units call
# the Rust binary directly (no shell in Nix strings), and each scheduled job
# is a typed timer (../agents/runner.nix). Nothing is declared unless
# agents.runner.enable is set, so no timer spends credit before then.
#
# Arguments (from host.nix):
#   enable       agents.runner.enable
#   agentRunner  packages.agent-runner (the Rust binary)
#   dsh          packages.dsh (the harness the runner drives)
#   requestFile  agents.runner.requestFile
#   scheduled    agents.runner.scheduled (typed timer items)
#   teamsJson    agents.teamsJson
{
  enable,
  agentRunner,
  dsh,
  requestFile,
  scheduled,
  teamsJson,
}:
{ lib, pkgs, ... }:
let
  teamsJsonFile = pkgs.writeText "teams.json" teamsJson;
  requestFileAbs = "/var/lib/dsh/work/${requestFile}";

  # systemd unit names cannot hold a `/`; the job keys are team/topic.
  unit = name: "agent-request-${lib.replaceStrings [ "/" ] [ "-" ] name}";

  requestServices = lib.mapAttrs' (
    name: item:
    lib.nameValuePair (unit name) {
      description = "Write the request for ${item.team}/${item.topic}, then run agent-runner";
      before = [ "agent-runner.service" ];
      wants = [ "agent-runner.service" ];
      serviceConfig = {
        Type = "oneshot";
        User = "dsh";
        Group = "agents";
        ExecStart = lib.escapeShellArgs [
          (lib.getExe agentRunner)
          "--create-request"
          requestFileAbs
          item.team
          item.topic
          item.brief
        ];
      };
    }
  ) scheduled;

  timers = lib.mapAttrs' (
    name: item:
    lib.nameValuePair (unit name) {
      description = "Schedule ${item.team}/${item.topic}: ${item.calendar}";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = item.calendar;
        Persistent = true;
      };
    }
  ) scheduled;
in
lib.mkIf enable {
  systemd.services = requestServices // {
    agent-runner = {
      description = "Run a dsh headless session from a typed request file, then commit and push its branch";
      after = [
        "dsh-work.service"
        "github-app-token.service"
      ];
      requires = [ "dsh-work.service" ];
      path = [
        pkgs.git
        dsh
      ];
      environment = {
        WORKTREE_ROOT = "/var/lib/dsh/work";
        TEAMS_JSON_FILE = "${teamsJsonFile}";
        DSH_HOME = "/var/lib/dsh";
        HOME = "/var/lib/dsh";
      };
      serviceConfig = {
        Type = "oneshot";
        User = "dsh";
        Group = "agents";
        WorkingDirectory = "/var/lib/dsh/work";
        EnvironmentFile = "/run/agents/openrouter.env";
        ExecStart = lib.escapeShellArgs [
          (lib.getExe agentRunner)
          requestFileAbs
        ];
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [ "/var/lib/dsh" ];
        PrivateTmp = true;
        NoNewPrivileges = true;
      };
    };
  };

  systemd.timers = timers;
}
