# Trading as declarations: brokerages are backends, strategies run on them.
#
#   trading.backends.<name> = { account; adapter; stage; }
#       a brokerage account (a held account with the brokerage role) and the
#       NautilusTrader adapter that reaches it. stage is how far it may go:
#       backtest, then paper, then live; live orders will be a spend action
#       (modules/governance), so no agent ever places one.
#   trading.strategies.<name> = { kind; backend; symbol; bar; params; }
#       one strategy on one instrument of one backend.
#
#   nix run .#trade -- backtest <strategy> <bars.csv>
#   nix run .#trade -- bars <symbol> <step> [period]     Public's bars as CSV
#   nix run .#trade -- paper <strategy> [bars.csv] [--all]
#
# Backtests touch no account: a simulated venue named after the backend, with
# a simulated balance. Bars come from anywhere with the columns in _trade.py.
# `bars` and `paper` read Public through our adapter (_public.py) under the
# `public` secretspec profile, asking governance-authorize first, as the
# matching `brokerage` commands would: paper preflights orders at Public,
# which places nothing. So they are the owner's: no agent holds Public.
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

  strategy = types.submodule {
    options = {
      kind = mkOption {
        type = types.enum [ "ema-cross" ];
        description = "A strategy _trade.py knows how to build.";
      };
      backend = mkOption { type = types.enum (lib.attrNames cfg.backends); };
      symbol = mkOption { type = types.strMatching "[A-Z][A-Z0-9.]*"; };
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
        type = types.submodule {
          options = {
            tradeSize = mkOption { type = types.ints.positive; };
            fastPeriod = mkOption { type = types.ints.positive; };
            slowPeriod = mkOption { type = types.ints.positive; };
          };
        };
      };
    };
  };

  problems = lib.concatLists (
    lib.mapAttrsToList (
      name: s:
      lib.optional (
        s.params.fastPeriod >= s.params.slowPeriod
      ) "trading.strategies.${name}: fastPeriod must be below slowPeriod"
    ) cfg.strategies
  );

  declared = lib.mapAttrs (
    _: s:
    s
    // {
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
    trading.strategies.ema-cross-spy = {
      kind = "ema-cross";
      backend = "public";
      symbol = "SPY";
      params = {
        tradeSize = 10;
        fastPeriod = 10;
        slowPeriod = 20;
      };
    };

    perSystem =
      { pkgs, config, ... }:
      let
        python = pkgs.python313.withPackages (_: [ config.packages.nautilus-trader ]);
        scripts = pkgs.linkFarm "trade-scripts" {
          "trade.py" = ./_trade.py;
          "_public.py" = ./_public.py;
        };
        # The engine itself, with whatever Public credentials the caller set.
        run = pkgs.writeShellApplication {
          name = "trade-run";
          runtimeInputs = [ python ];
          text = builtins.seq (lib.assertMsg (problems == [ ]) (lib.concatStringsSep "\n" problems)) ''
            export TRADE_STRATEGIES=${lib.escapeShellArg (builtins.toJSON declared)}
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
            case "''${1:-}" in
              bars | paper)
                export PROTON_PASS_KEY_PROVIDER=''${PROTON_PASS_KEY_PROVIDER:-fs}
                governance-authorize public:historicdata-bars ${top.trading.backends.public.account}
                [ "$1" = bars ] || governance-authorize public:order-preflight-single ${top.trading.backends.public.account}
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
              jq -s '{backtest: .[0], paper: .[1]}' result.json paper.json > $out
            '';
      };
  };
}
