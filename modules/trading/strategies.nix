# Trading as declarations: brokerages are backends, strategies run on them.
#
#   trading.backends.<name> = { account; adapter; stage; }
#       a brokerage account (a held account with the brokerage role) and the
#       NautilusTrader adapter that reaches it. stage is how far it may go:
#       backtest, then paper, then live; live orders will be a spend action
#       (modules/governance), so no agent ever places one.
#   trading.strategies.<name> = { kind; backend; symbol; bar; params; option;
#                                 event; decisions; holdDays;
#                                 maxDayTradesPer5Days; }
#       one strategy on one instrument (or, for event-rule, one category of
#       event contracts) of one backend. holdDays is the least number of
#       days a position is held (0: it may be closed the day it opens);
#       maxDayTradesPer5Days is the most round trips the strategy can open
#       and close on one day over five business days, defaulting per kind
#       (0 with holdDays ≥ 1; ema-cross on daily bars 0, since one bar is
#       one day; agent-option and event-rule 5, one proposal a day that
#       nothing stops closing the same day) and held under FINRA's
#       pattern-day-trader rule by modules/compliance.
#
#   nix run .#trade -- backtest <strategy> <bars.csv>
#   nix run .#trade -- bars <symbol> <step> [period]     Public's bars as CSV
#   nix run .#trade -- paper <strategy> [bars.csv] [--all]
#   nix run .#trade -- propose <strategy> [date] [--forecasts file]
#   nix run .#trade -- paper-day <strategy> [date] [--forecasts file]
#
# Backtests touch no account: a simulated venue named after the backend, with
# a simulated balance. Bars come from anywhere with the columns in _trade.py.
# `bars`, `paper`, `propose` and `paper-day` read Public through our adapter
# (_public.py) under the `public` secretspec profile, asking
# governance-authorize first, as the matching `brokerage` commands would:
# they preflight orders at Public, which places nothing. So they are the
# owner's: no agent holds Public.
#
# Kinds: ema-cross (the engine's example), agent-option (the research
# teams' decision into one option, ./_propose.py) and event-rule (the
# owner's framing of 2026-11-04: Public's event contracts, Kalshi's, priced
# by deterministic weather rules, ./_weather.py; never a model that talks).
{ lib, config, ... }:
let
  inherit (lib) mkOption types;
  top = config;
  cfg = config.trading;
  held = config.accounts.held;
  brokerages = lib.attrNames (
    lib.filterAttrs (_: a: lib.elem "brokerage" (config.accounts.roles.${a.provider} or [ ])) held
  );

  backend = types.submodule {
    options = {
      account = mkOption {
        type = types.enum brokerages;
        description = "A held account with the brokerage role.";
      };
      adapter = mkOption {
        type = types.enum [
          "public" # ours: Public's API has no NautilusTrader adapter
          "interactive-brokers" # NautilusTrader's own
        ];
      };
      stage = mkOption {
        type = types.enum [
          "backtest"
          "paper"
          "live"
        ];
        default = "backtest";
      };
    };
  };

  strategy = types.submodule (
    { config, ... }:
    {
      options = {
        holdDays = mkOption {
          type = types.ints.unsigned;
          default = 0;
          description = ''
            The least number of days a position is held once opened: 0 lets
            the strategy close it the same day, 1 or more holds it overnight,
            so no round trip is a day trade.
          '';
        };
        maxDayTradesPer5Days = mkOption {
          type = types.ints.unsigned;
          default =
            if config.holdDays >= 1 then
              0
            else
              {
                ema-cross = if lib.hasSuffix "-DAY" config.bar then 0 else 5;
                agent-option = 5;
                event-rule = 5;
              }
              .${config.kind};
          defaultText = lib.literalMD "0 with `holdDays` ≥ 1; else per kind: ema-cross 0 on daily bars and 5 below, agent-option 5, event-rule 5";
          description = ''
            The most round trips (a buy and a sell of the same instrument on
            one business day) the strategy can make in five consecutive
            business days. modules/compliance holds it under FINRA's
            pattern-day-trader rule for the account it runs on.
          '';
        };
        kind = mkOption {
          type = types.enum [
            "ema-cross"
            # The day's research decision into one defined-risk option within
            # the limits (./_propose.py, ./limits.nix).
            "agent-option"
            # Event contracts by rule: a forecast's probability against the
            # contract's price (./_weather.py, ./_propose.py).
            "event-rule"
          ];
          description = "A strategy _trade.py knows how to build.";
        };
        event = mkOption {
          type = types.nullOr (
            types.submodule {
              options = {
                category = mkOption {
                  type = types.str;
                  description = "Public's event category, as `event-contracts categories` names it.";
                };
                subcategory = mkOption {
                  type = types.nullOr types.str;
                  default = null;
                  description = "One of the category's subcategories, or null for the whole category.";
                };
                minEdge = mkOption {
                  type = types.numbers.between 0.0 1.0;
                  description = "The least model-probability-over-price a contract needs to be proposed.";
                };
                maxContracts = mkOption {
                  type = types.ints.positive;
                  description = "The most contracts one proposal buys.";
                };
                questions = mkOption {
                  type = types.nonEmptyListOf (
                    types.enum [
                      "rain-month"
                      "snow-month"
                      "high-temp-day"
                    ]
                  );
                  description = "The question shapes the rules may trade (_weather.py's QUESTIONS); everything else is skipped.";
                };
                source = mkOption {
                  type = types.enum [
                    "open-meteo"
                    "nws"
                  ];
                  default = "open-meteo";
                  description = "Where live forecasts come from (research.dataSources); --forecasts FILE replaces it.";
                };
              };
            }
          );
          default = null;
          description = "For event-rule: which contracts, which questions, and how much edge.";
        };
        option = mkOption {
          type = types.nullOr (
            types.submodule {
              options = {
                expiryDaysMin = mkOption {
                  type = types.ints.positive;
                  default = 7;
                };
                expiryDaysMax = mkOption {
                  type = types.ints.positive;
                  default = 21;
                };
                minAbsDelta = mkOption {
                  type = types.numbers.between 0.0 1.0;
                  default = 0.15;
                };
              };
            }
          );
          default = null;
          description = "For agent-option: how the contract is chosen.";
        };
        decisions = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "For agent-option: the directory of research decisions, <dir>/<date>/<symbol>.json; for event-rule, the directory of the day's state and paper records.";
        };
        backend = mkOption { type = types.enum (lib.attrNames cfg.backends); };
        symbol = mkOption {
          type = types.strMatching "[A-Z][A-Z0-9.]*";
          description = "The instrument; for event-rule, the exchange whose contracts Public lists (KALSHI, the prefix of every event symbol).";
        };
        bar = mkOption {
          type = types.strMatching "[0-9]+-(SECOND|MINUTE|HOUR|DAY)";
          default = "1-DAY";
          description = "The bar step, as NautilusTrader writes it.";
        };
        startingUsd = mkOption {
          type = types.ints.positive;
          default = 10000;
          description = "The simulated balance a backtest starts with.";
        };
        params = mkOption {
          type = types.nullOr (
            types.submodule {
              options = {
                tradeSize = mkOption { type = types.ints.positive; };
                fastPeriod = mkOption { type = types.ints.positive; };
                slowPeriod = mkOption { type = types.ints.positive; };
              };
            }
          );
          default = null;
          description = "For ema-cross.";
        };
      };
    }
  );

  problems = lib.concatLists (
    lib.mapAttrsToList (
      name: s:
      lib.optional (
        s.kind == "ema-cross" && (s.params == null || s.params.fastPeriod >= s.params.slowPeriod)
      ) "trading.strategies.${name}: ema-cross needs params with fastPeriod below slowPeriod"
      ++ lib.optional (
        s.kind == "agent-option" && (s.option == null || s.decisions == null)
      ) "trading.strategies.${name}: agent-option needs option and decisions"
      ++ lib.optional (
        s.kind == "event-rule" && (s.event == null || s.decisions == null)
      ) "trading.strategies.${name}: event-rule needs event and decisions"
      ++ lib.optional (
        lib.elem s.kind [
          "agent-option"
          "event-rule"
        ]
        && !(cfg.limits ? ${s.backend})
      ) "trading.strategies.${name}: no trading.limits.${s.backend}"
      ++ lib.optional (
        s.kind == "event-rule"
        && s.event != null
        && !(config.research.dataSources ? ${sourceKey s.event.source})
      ) "trading.strategies.${name}: research.dataSources has no ${sourceKey s.event.source}"
    ) cfg.strategies
  );
  sourceKey = lib.replaceStrings [ "-" ] [ "_" ];
  eventRule = lib.attrNames (lib.filterAttrs (_: s: s.kind == "event-rule") cfg.strategies);

  declared = lib.mapAttrs (
    name: s:
    s
    // {
      inherit name;
      venue = lib.toUpper (lib.replaceStrings [ "-" ] [ "_" ] s.backend);
    }
  ) cfg.strategies;
in
{
  options.trading = {
    backends = mkOption {
      type = types.attrsOf backend;
      default = { };
    };
    strategies = mkOption {
      type = types.attrsOf strategy;
      default = { };
    };
  };

  config = {
    # Public first: your account, through an adapter of our own. Backtests
    # only until the adapter exists and the account question is settled
    # (HANDOFF.md).
    trading.backends.public = {
      account = "public-mirazo";
      adapter = "public";
    };

    # The engine's own example, kept as the reference every backtest check
    # runs: it proves the packaged engine trades end to end.
    trading.strategies = {
      ema-cross-spy = {
        kind = "ema-cross";
        backend = "public";
        symbol = "SPY";
        params = {
          tradeSize = 10;
          fastPeriod = 10;
          slowPeriod = 20;
        };
      };
      # The plan of 2026-11-02: the research teams' daily decision on SPY,
      # as one long call or put within the limits; placed only by the
      # owner (`trade place`), and only once the strategy's stage is live.
      spy-agents = {
        kind = "agent-option";
        backend = "public";
        symbol = "SPY";
        option = { };
        decisions = "research";
        # The option is held at least overnight: the day's decision opens
        # it, a later day's closes it, so no round trip is a day trade and
        # the brokerage account (margin, far under $25,000) never meets
        # FINRA's pattern-day-trader rule (modules/compliance, 2026-11-04).
        holdDays = 1;
      };
      # The owner's framing of 2026-11-04: Kalshi's weather contracts on
      # Public, each settling on an observation (its worst case the price
      # paid), priced by the rules in _weather.py from NWS or Open-Meteo
      # forecasts. The whole "Climate and Weather" category is read; only
      # the question shapes named here are ever traded. Paper first: the
      # stage gate (./stages.nix) holds it at research.
      weather-rules = {
        kind = "event-rule";
        backend = "public";
        symbol = "KALSHI";
        event = {
          category = "Climate and Weather";
          minEdge = 0.15;
          maxContracts = 10;
          questions = [
            "rain-month"
            "snow-month"
            "high-temp-day"
          ];
        };
        decisions = "research";
        # Contracts are held to settlement or at least overnight, never
        # sold the day they are bought: at the default cadence (one
        # proposal a day, closable the same day) the strategy would be five
        # day trades in five days on a margin account under $25,000, which
        # FINRA Rule 4210(f)(8)(B) restricts (modules/compliance, 2026-11-04).
        holdDays = 1;
      };
    };

    # Public lists event contracts through its API (the pinned CLI's
    # `event-contracts` and EVENTCONTRACT instrument type); the strategy
    # relies on it, so the account's plan must state it.
    accounts.demands = map (name: {
      account = cfg.backends.${cfg.strategies.${name}.backend}.account;
      capability = "eventContractsApi";
      need = true;
      why = "trading.strategies.${name} proposes event contracts";
    }) eventRule;

    perSystem =
      { pkgs, config, ... }:
      let
        python = pkgs.python313.withPackages (_: [ config.packages.nautilus-trader ]);
        scripts = pkgs.linkFarm "trade-scripts" {
          "trade.py" = ./_trade.py;
          "_public.py" = ./_public.py;
          "_propose.py" = ./_propose.py;
          "_weather.py" = ./_weather.py;
          "_weather_test.py" = ./_weather_test.py;
        };
        # The event-rule strategies, for the wrapper's authorizations.
        eventRulePattern = if eventRule == [ ] then "--none--" else lib.concatStringsSep "|" eventRule;
        # The engine itself, with whatever Public credentials the caller set.
        run = pkgs.writeShellApplication {
          name = "trade-run";
          runtimeInputs = [ python ];
          text = builtins.seq (lib.assertMsg (problems == [ ]) (lib.concatStringsSep "\n" problems)) ''
            export TRADE_STRATEGIES=${lib.escapeShellArg (builtins.toJSON declared)}
            export TRADE_LIMITS=${lib.escapeShellArg (builtins.toJSON cfg.limits)}
            exec python3 -I ${scripts}/trade.py "$@"
          '';
        };
        trade = pkgs.writeShellApplication {
          name = "trade";
          runtimeInputs = [
            run
            config.packages.secretspec
            config.packages.pass-cli
            config.packages.governance-authorize
          ];
          text = builtins.seq top.accounts.checked ''
            account=${top.trading.backends.public.account}
            case "''${1:-}" in
              account | bars | paper | propose | paper-day | place)
                export PROTON_PASS_KEY_PROVIDER=''${PROTON_PASS_KEY_PROVIDER:-fs}
                case "$1" in
                  account) governance-authorize public:accounts-list "$account" ;;
                  bars) governance-authorize public:historicdata-bars "$account" ;;
                  paper)
                    governance-authorize public:historicdata-bars "$account"
                    governance-authorize public:order-preflight-single "$account" ;;
                  propose | paper-day)
                    case "''${2:-}" in
                      ${eventRulePattern})
                        governance-authorize public:event-contracts-summary "$account"
                        governance-authorize public:event-contracts-details "$account"
                        governance-authorize public:market-quotes "$account" ;;
                      *) governance-authorize public:market-option-chain "$account" ;;
                    esac
                    governance-authorize public:order-preflight-single "$account" ;;
                  # The one spend: the controller's, never an agent's (modules/governance).
                  place)
                    governance-authorize public:order-preflight-single "$account"
                    governance-authorize public:order-place "$account" ;;
                esac
                exec secretspec run --file ${config.packages.secretspec-toml} --profile public \
                  --reason "trade $*" -- trade-run "$@"
                ;;
              *) exec trade-run "$@" ;;
            esac
          '';
        };
      in
      {
        packages.trade = trade;

        # A deterministic random walk with a trend change, so the EMA cross
        # must buy and sell at least once.
        checks.trading-backtest =
          pkgs.runCommand "trading-backtest"
            {
              nativeBuildInputs = [
                run
                pkgs.jq
              ];
            }
            ''
              ${pkgs.python313}/bin/python3 -I - > bars.csv <<'EOF'
              import datetime, random
              random.seed(7)
              t = datetime.datetime(2025, 1, 2, 21, tzinfo=datetime.timezone.utc)
              p = 100.0
              print("timestamp,open,high,low,close,volume")
              for i in range(300):
                  drift = 0.4 if (i // 60) % 2 == 0 else -0.4
                  o = p
                  p = max(1.0, p + drift + random.uniform(-1, 1))
                  print(f"{t.isoformat()},{o:.2f},{max(o, p) + 0.5:.2f},{min(o, p) - 0.5:.2f},{p:.2f},{random.randint(1000, 5000)}")
                  t += datetime.timedelta(days=1)
              EOF
              trade-run backtest ema-cross-spy bars.csv > result.json
              jq -e '.bars == 300 and .orders_filled >= 2' result.json

              # The Public adapter against a stand-in for Public's API: the
              # same bars back, BUY preflights taken, SELLs refused.
              ${pkgs.python313}/bin/python3 -I ${./_stub_public.py} bars.csv > port &
              while [ ! -s port ]; do sleep 0.1; done
              export PUBLIC_API_BASE_URL=http://127.0.0.1:$(cat port) PUBLIC_PERSONAL_SECRET=stub-secret
              trade-run bars SPY 1-DAY > public.csv
              [ "$(wc -l < public.csv)" = 301 ]
              trade-run paper ema-cross-spy --all > paper.json
              jq -e --slurpfile b result.json '.orders_filled == $b[0].orders_filled
                and (.preflight | length) >= 2
                and any(.preflight[]; .accepted and .preflight.estimatedCost == "1000.00")
                and any(.preflight[]; (.accepted | not) and .refused_by == "public" and .status == 400)' paper.json

              # The agent-option strategy against the stub's chain: a BUY
              # decision becomes one call within the $25 cap at |delta| ≥
              # 0.15, preflighted and accepted; HOLD proposes nothing; a
              # stopped day refuses; `place` places and reads it back.
              last=$(tail -1 bars.csv | cut -d, -f1 | cut -c1-10)
              mkdir -p research/$last
              echo '{"decision": "BUY", "rationale": "the check"}' > research/$last/SPY.json
              trade-run propose spy-agents "$last" > proposal.json
              jq -e --argjson cap ${toString cfg.limits.public.maxPremiumUsd} \
                '.proposal.admissible and .proposal.accepted and .proposal.max_loss_usd <= $cap
                 and (.proposal.contract.delta | fabs) >= 0.15 and .proposal.kind == "long-call"
                 and .proposal.order.instrument.type == "OPTION" and .proposal.order.orderType == "LIMIT"' proposal.json
              echo '{"decision": "HOLD"}' > research/$last/SPY.json
              trade-run propose spy-agents "$last" | jq -e '.proposal == null'
              echo '{"decision": "SELL", "rationale": "the check"}' > research/$last/SPY.json
              echo '{"openPositions": 0, "lossUsd": ${toString cfg.limits.public.dailyLossStopUsd}}' > research/state.json
              trade-run propose spy-agents "$last" | jq -e '.proposal.kind == "long-put" and (.proposal.admissible | not)'
              rm research/state.json
              # The gate: the strategy is at research (./stages.nix), so
              # `place` refuses it whatever the proposal says.
              if trade-run place proposal.json 2>refused; then exit 1; fi
              grep -q "not live: nothing is placed" refused
              # The adapter's own placing and reading back, against the stub.
              ${pkgs.python313}/bin/python3 -I - > placed.json <<'EOF'
              import json, sys
              sys.path.insert(0, "${scripts}")
              import _public
              order = json.load(open("proposal.json"))["proposal"]["order"]
              api = _public.Public()
              placed = api.place(order)
              print(json.dumps({"placed": placed, "status": api.order(placed["orderId"])}))
              EOF
              jq -e '.status.status == "FILLED" and .placed.orderId == .status.orderId' placed.json

              # The event-rule strategy against the stub's weather contracts
              # (two open events, one resolved) with the fixture forecasts:
              # New York's high is far above the "72° or above" band's $0.20,
              # so that YES is proposed, within the contract cap, preflighted
              # and accepted; with the forecast at 68° every edge is small
              # and nothing is proposed; a day at its take-profit refuses;
              # paper-day records the day.
              cp ${./_json/forecasts.json} forecasts.json
              trade-run propose weather-rules 2026-11-04 --forecasts forecasts.json > weather.json
              jq -e --argjson cap ${toString cfg.limits.public.maxContractPriceUsd} \
                --argjson min ${toString cfg.strategies.weather-rules.event.minEdge} \
                '.proposal.admissible and .proposal.accepted and .proposal.kind == "event-yes"
                 and .proposal.max_loss_usd <= $cap and .proposal.contract.edge >= 0.5
                 and .proposal.contract.contract == "KALSHI.KXHIGHNY-26NOV06-T72.Y"
                 and .proposal.contract.edge >= $min
                 and .proposal.order.instrument.type == "EVENTCONTRACT" and .proposal.order.orderType == "LIMIT"
                 and .proposal.order.orderSide == "BUY" and .proposal.order.limitPrice == "0.20"
                 and (.proposal.preflight.estimatedCost | tonumber) == .proposal.max_loss_usd
                 and (.considered | length) == 8
                 and all(.skipped[]; .why != "a question shape the rules do not handle")' weather.json
              jq '.cities["New York"].daily |= map(if .date == "2026-11-06" then .high_f = 68 else . end)' forecasts.json > small.json
              trade-run propose weather-rules 2026-11-04 --forecasts small.json \
                | jq -e --argjson min ${toString cfg.strategies.weather-rules.event.minEdge} \
                  '.proposal == null and ([.considered[].edge] | max) < $min'
              echo '{"openPositions": 0, "lossUsd": 0, "gainUsd": ${toString cfg.limits.public.dailyTakeProfitUsd}}' > research/state.json
              trade-run propose weather-rules 2026-11-04 --forecasts forecasts.json \
                | jq -e '(.proposal.admissible | not) and (.proposal.refused_because | any(test("take-profit")))'
              rm research/state.json
              trade-run paper-day weather-rules 2026-11-04 --forecasts forecasts.json | jq -e '.recorded'
              [ -s research/paper/2026-11-04-weather-rules.json ]
              # The adapter's event endpoints against the stub: summaries
              # with and without resolved events, quotes by EVENTCONTRACT,
              # a contract's bars.
              ${pkgs.python313}/bin/python3 -I - > events.json <<'EOF'
              import json, sys
              sys.path.insert(0, "${scripts}")
              import _public
              api = _public.Public()
              every = api.event_contracts(category="Climate and Weather", include_resolved=True)
              open_ = api.event_contracts(category="Climate and Weather")
              sym = "KALSHI.KXHIGHNY-26NOV06-T72.Y"
              print(json.dumps({
                  "all": len(every), "open": len(open_),
                  "quotes": api.quotes([(sym, "EVENTCONTRACT")]),
                  "bars": api.event_contract_bars("KALSHI.KXHIGHNY-26NOV06-EVENT", "WEEK", [sym]),
              }))
              EOF
              jq -e '.all == 3 and .open == 2 and .quotes[0].outcome == "SUCCESS" and .quotes[0].ask == "0.20"
                     and (.bars.charts | length) == 1 and .bars.period == "WEEK"' events.json
              jq -s '{backtest: .[0], paper: .[1], proposal: .[2], placed: .[3], weather: .[4], events: .[5]}' \
                result.json paper.json proposal.json placed.json weather.json events.json > $out
            '';

        # The weather rules over the fixture, offline: the parser's shapes
        # and refusals, the probabilities, the two live sources' parsers.
        checks.trading-weather = pkgs.runCommand "trading-weather" { } ''
          ${pkgs.python313}/bin/python3 -I ${scripts}/_weather_test.py ${./_json/forecasts.json}
          touch $out
        '';
      };
  };
}
