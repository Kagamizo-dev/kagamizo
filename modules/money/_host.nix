# The ledger on jingzo-host (NixOS; imported by ../hetzner/host.nix with the
# host's build of `ledger`): a timer that reads the brokerage's books into
# `dir` nightly, as the accounting swarm (modules/governance/swarms.nix
# grants it read on the account). Nothing is declared on the host while
# `enable` is false (money.ledger.enable): the owner has not yet said
# nightly reads are allowed.
#
# The unit signs pass-cli in with the host's agent token (../migration/
# _host.nix does the same) and reads Public through the `public-host`
# profile: the host's copy of the personal secret in Kagamizo-Host
# (../public/secrets.nix).
{
  ledger,
  passCli,
  enable,
  dir,
  at,
  agent,
}:
{ lib, pkgs, ... }:
let
  tokenFile = "/var/lib/kagamizo/host-token";
in
{
  config = lib.mkIf enable {
    environment.systemPackages = [ ledger ];
    systemd = {
      tmpfiles.rules = [ "d ${dir} 0700 root root - -" ];
      services.money-ledger = {
        description = "The brokerage's books, read into ${dir}";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        path = [
          ledger
          passCli
          pkgs.coreutils
        ];
        serviceConfig.Type = "oneshot";
        script = ''
          set -euo pipefail
          [ -r ${tokenFile} ] || { echo "money-ledger: no host token at ${tokenFile}; idle" >&2; exit 0; }
          export PROTON_PASS_KEY_PROVIDER=fs HOME=/root
          export PROTON_PASS_AGENT_REASON="jingzo-host: the nightly ledger"
          pass-cli info >/dev/null 2>&1 || pass-cli login --pat "$(cat ${tokenFile})" >/dev/null
          export KAGAMIZO_PRINCIPAL=agent:${agent} MONEY_LEDGER_DIR=${dir} PUBLIC_PROFILE=public-host
          ledger public
        '';
      };
      timers.money-ledger = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = at;
          Persistent = true;
        };
      };
    };
  };
}
