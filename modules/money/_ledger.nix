# The brokerage's books, read into typed records: one file a day under a
# declared directory on the host (never the repo), from the reads
# `brokerage` governs.
#
#   ledger public [DATE]     the brokerage account's portfolio, its whole
#                            history (every page), its orders of the last
#                            30 days and its unrealized tax lots, typed by
#                            money-ledger (./_src/src/bin) into
#                            $MONEY_LEDGER_DIR/money.ledger.public.<date>.json
#
# Every read goes through `brokerage --json ...` (modules/public): api-check,
# the authorization states and governance-authorize decide each one, as the
# actions public:portfolio-show, public:history-list, public:order-search and
# public:taxlots-list. On the host (./_host.nix) it runs nightly as the
# accounting-mirazo swarm, which modules/governance/swarms.nix grants read
# on public-mirazo; `money.ledger.enable` is false until the owner says
# nightly reads are allowed.
{ lib, config, ... }:
let
  inherit (lib) mkOption types;
  cfg = config.money.ledger;
in
{
  options.money.ledger = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = "Whether jingzo-host reads the ledger nightly (the owner's answer is pending).";
    };
    account = mkOption {
      type = types.enum (
        lib.attrNames (lib.filterAttrs (_: a: a.provider == "public") config.accounts.held)
      );
      default = "public-mirazo";
      description = "The held Public account the ledger reads.";
    };
    dir = mkOption {
      type = types.strMatching "/.+";
      default = "/var/lib/money";
      description = "Where the records go on the host (MONEY_LEDGER_DIR elsewhere).";
    };
    at = mkOption {
      type = types.str;
      default = "*-*-* 02:40:00";
      description = "When the host reads (systemd calendar, UTC).";
    };
    agent = mkOption {
      type = types.enum (lib.attrNames config.governance.agents);
      default = "accounting-mirazo";
      description = "The swarm the host's unit runs as (KAGAMIZO_PRINCIPAL).";
    };
  };

  config.accounts.demands = [
    {
      inherit (cfg) account;
      capability = "historyApi";
      need = true;
      why = "ledger public reads the account's history";
    }
  ];

  config.perSystem =
    { pkgs, config, ... }:
    {
      packages.ledger = pkgs.writeShellApplication {
        name = "ledger";
        runtimeInputs = [
          config.packages.brokerage
          config.packages.money-report
          pkgs.jq
          pkgs.coreutils
        ];
        text = ''
          usage="usage: ledger public [DATE]  (MONEY_LEDGER_DIR, default ${cfg.dir})"
          [ "''${1:-}" = public ] || { echo "$usage" >&2; exit 2; }
          date=''${2:-$(date -u +%F)}
          dir=''${MONEY_LEDGER_DIR:-${cfg.dir}}
          mkdir -p "$dir"
          work=$(mktemp -d)
          trap 'rm -rf "$work"' EXIT
          brokerage --json portfolio show >"$work/portfolio.json"
          account_id=$(jq -r .accountId "$work/portfolio.json")
          # Every page of the history, one per line.
          : >"$work/history.jsonl"
          token=
          for _ in $(seq 1 100); do
            if [ -n "$token" ]; then
              brokerage --json history list --page-size 100 --next-token "$token" >"$work/page.json"
            else
              brokerage --json history list --page-size 100 >"$work/page.json"
            fi
            jq -c . "$work/page.json" >>"$work/history.jsonl"
            token=$(jq -r '.nextToken // empty' "$work/page.json")
            [ -n "$token" ] || break
          done
          brokerage --json order search >"$work/orders.json"
          brokerage --json taxlots list >"$work/taxlots.json"
          out=$dir/money.ledger.public.$date.json
          money-ledger ${cfg.account} "$account_id" "$(date -u +%FT%TZ)" \
            "$work/portfolio.json" "$work/history.jsonl" "$work/orders.json" "$work/taxlots.json" "$out"
          chmod 600 "$out"
          echo "ledger: $out ($(jq -r '"\(.history | length) transactions, \(.orders | length) orders, \(.taxLots.lots | length) lots, cash \(.portfolio.cash)"' "$out"))"
        '';
      };

      # The record typed from the observed shapes of an empty account.
      checks.money-ledger-run =
        pkgs.runCommand "money-ledger-run"
          {
            nativeBuildInputs = [
              config.packages.money-report
              pkgs.jq
            ];
          }
          ''
            t=${./_src/_test/public}
            money-ledger public-mirazo 5OI41709 2026-11-04T02:40:00Z \
              $t/portfolio.json $t/history.jsonl $t/orders.json $t/taxlots.json out.json
            jq -e '.schema == "money.ledger.public/1" and .portfolio.cash == "0.00" and .history == []' out.json >/dev/null
            # Another account's portfolio is refused.
            if money-ledger public-mirazo 2OP05949 t $t/portfolio.json $t/history.jsonl $t/orders.json $t/taxlots.json no.json 2>/dev/null; then
              echo "accepted a portfolio of another account" >&2; exit 1
            fi
            touch $out
          '';
    };
}
