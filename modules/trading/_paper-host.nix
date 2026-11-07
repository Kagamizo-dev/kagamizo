# The paper-trading units on jingzo-host (./paper.nix), imported by
# ../hetzner/host.nix. Per strategy: a paper day and a settlement, each a
# oneshot that trading-host starts (no shell): it signs pass-cli in with the
# host's token, then runs `trade`, which asks governance-authorize as the
# agent and reads Public through the `public-host` profile.
{
  enable,
  strategies,
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
in
lib.mkIf enable {
  environment.systemPackages = [ trade ];
  systemd = {
    tmpfiles.rules = [ "d ${dir} 0700 root root - -" ];
    services = each (s: [
      (lib.nameValuePair "trading-paper-day-${s}" (unit "paper-day" s))
      (lib.nameValuePair "trading-paper-settle-${s}" (unit "paper-settle" s))
    ]);
    timers = each (s: [
      (lib.nameValuePair "trading-paper-day-${s}" (timer dayAt))
      (lib.nameValuePair "trading-paper-settle-${s}" (timer settleAt))
    ]);
  };
}
