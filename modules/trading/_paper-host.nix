# The paper-trading units on jingzo-host (./paper.nix), imported by
# ../hetzner/host.nix. Per strategy: a paper day, its rehearsal of the live
# path up to placing (started when the paper day succeeds) and a settlement
# (for a dry-run strategy, only when it settles without a model: `settles`),
# each a
# oneshot that trading-host starts (no shell): it signs pass-cli in with the
# host's token, then runs `trade`, which asks governance-authorize as the
# agent and reads Public through the `public-host` profile.
{
  enable,
  strategies,
  dryRun,
  settles,
  symbols,
  research,
  dayAt,
  settleAt,
  agent,
  dir,
  trade,
  launcher,
  passCli,
}:
{ lib, ... }:
let
  tokenFile = "/var/lib/kagamizo/host-token";
  unit = command: strategy: {
    description = "trade ${command} ${strategy}";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    path = [ passCli ];
    environment = {
      HOME = "/root";
      PROTON_PASS_KEY_PROVIDER = "fs";
      PROTON_PASS_AGENT_REASON = "jingzo-host: trade ${command} ${strategy}";
      KAGAMIZO_PRINCIPAL = "agent:${agent}";
      PUBLIC_PROFILE = "public-host";
    };
    serviceConfig = {
      Type = "oneshot";
      WorkingDirectory = dir;
      ExecStart = lib.escapeShellArgs [
        launcher
        tokenFile
        (lib.getExe trade)
        command
        strategy
      ];
    };
  };
  timer = at: {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = at;
      Persistent = true;
    };
  };
  each = f: lib.listToAttrs (lib.concatMap f strategies);
  dry = f: lib.listToAttrs (lib.concatMap f dryRun.strategies);
  # The dry run's research: TradingAgents on the host's small model, writing
  # the day's decision where the strategy reads it; on success, the paper day.
  researchUnit =
    s:
    let
      cheap = dryRun.backend == "cheap";
    in
    {
      description = "research --${dryRun.backend} run ${symbols.${s}} today (the dry run of ${s})";
      after = [ "network-online.target" ] ++ lib.optional (!cheap) "llama-cpp.service";
      wants = [ "network-online.target" ];
      requires = lib.optional (!cheap) "llama-cpp.service";
      onSuccess = [ "trading-paper-day-${s}.service" ];
      path = lib.optional cheap passCli;
      environment = {
        HOME = "/root";
      }
      // lib.optionalAttrs cheap {
        # The host's own capped key, through its vault (pass-cli signed in
        # by trading-host with the host's token).
        PROTON_PASS_KEY_PROVIDER = "fs";
        PROTON_PASS_AGENT_REASON = "jingzo-host: research --cheap (${s})";
        RESEARCH_PROFILE = "research-host";
      };
      serviceConfig = {
        Type = "oneshot";
        WorkingDirectory = dir;
        ExecStart = lib.escapeShellArgs (
          lib.optionals cheap [
            launcher
            tokenFile
          ]
          ++ [
            (lib.getExe research)
            "--${dryRun.backend}"
            "run"
            symbols.${s}
            "today"
          ]
        );
      };
    };
in
lib.mkIf enable {
  environment.systemPackages = [ trade ];
  systemd = {
    tmpfiles.rules = [ "d ${dir} 0700 root root - -" ];
    services =
      dry (s: [
        (lib.nameValuePair "trading-research-${s}" (researchUnit s))
        (lib.nameValuePair "trading-paper-day-${s}" (
          unit "paper-day" s
          // {
            onSuccess = [ "trading-rehearse-${s}.service" ];
          }
        ))
        (lib.nameValuePair "trading-rehearse-${s}" (unit "rehearse" s))
      ])
      // lib.listToAttrs (
        map (s: lib.nameValuePair "trading-paper-settle-${s}" (unit "paper-settle" s)) settles
      )
      // each (s: [
        # After a paper day succeeds, its rehearsal: the live path up to placing.
        (lib.nameValuePair "trading-paper-day-${s}" (
          unit "paper-day" s
          // {
            onSuccess = [ "trading-rehearse-${s}.service" ];
          }
        ))
        (lib.nameValuePair "trading-rehearse-${s}" (unit "rehearse" s))
        (lib.nameValuePair "trading-paper-settle-${s}" (unit "paper-settle" s))
      ]);
    timers =
      dry (s: [ (lib.nameValuePair "trading-research-${s}" (timer dryRun.at)) ])
      // lib.listToAttrs (map (s: lib.nameValuePair "trading-paper-settle-${s}" (timer settleAt)) settles)
      // each (s: [
        (lib.nameValuePair "trading-paper-day-${s}" (timer dayAt))
        (lib.nameValuePair "trading-paper-settle-${s}" (timer settleAt))
      ]);
  };
}
