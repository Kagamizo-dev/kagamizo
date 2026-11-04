# The research loops of the trading plan (2026-11-02, part C):
# TradingAgents (TauricResearch, Apache-2.0, v0.7.1, arXiv 2412.20138),
# pinned as a flake input and built with this flake's nixpkgs: analysts, a
# bull/bear debate, a trader, risk and a portfolio manager, on any
# OpenAI-compatible endpoint. Here that is OpenRouter with the declared
# open-weight models, on the research key (openrouter.keys.research,
# $20 a month). Its decisions are files `trade propose` reads.
#
#   nix run .#research -- run SPY 2026-11-04        research/2026-11-04/SPY.json
#   nix run .#research -- sweep SPY,QQQ FROM TO --jobs 2
#   nix run .#research -- backtest SPY FROM TO      its own run_backtest
#
# Research reads markets only (Yahoo Finance, SEC EDGAR, FRED, Polymarket:
# research.dataSources, each with its host) and calls no broker, so it
# needs no account action and no Cedar grant; the research team runs it.
# nixpkgs' langchain, langgraph, pandas and yfinance are a little behind
# the pins in its pyproject (pythonRelaxDeps); the check imports the
# package and builds the graph, so a mismatch fails here, not on the host.
{
  lib,
  config,
  inputs,
  ...
}:
let
  inherit (lib) mkOption types;
  cfg = config.research;
  models = config.openrouter.models;
in
{
  options.research = {
    deepModel = mkOption {
      type = types.enum models;
      default = "deepseek/deepseek-v4-pro";
      description = "The managers' model (tier 3).";
    };
    quickModel = mkOption {
      type = types.enum models;
      default = config.openrouter.defaultModel;
      description = "The analysts', researchers' and trader's model (tier 2).";
    };
    debateRounds = mkOption {
      type = types.ints.positive;
      default = 1;
    };
    riskRounds = mkOption {
      type = types.ints.positive;
      default = 1;
    };
    maxTokens = mkOption {
      type = types.ints.positive;
      default = 4096;
      description = "Output cap per call, so an unbounded answer never runs the key down.";
    };
    dataVendors = mkOption {
      type = types.attrsOf types.str;
      default = {
        core_stock_apis = "yfinance";
        technical_indicators = "yfinance";
        fundamental_data = "sec_edgar,yfinance";
        news_data = "yfinance";
        macro_data = "fred";
        prediction_markets = "polymarket";
      };
      description = "TradingAgents' vendor chain per category, as its config names them.";
    };
    dataSources = mkOption {
      type = types.attrsOf (
        types.submodule {
          options = {
            hosts = mkOption { type = types.listOf types.str; };
            key = mkOption {
              type = types.nullOr types.str;
              default = null;
              description = "The environment variable of its key, when it needs one.";
            };
          };
        }
      );
      readOnly = true;
      default = {
        yfinance.hosts = [
          "query1.finance.yahoo.com"
          "query2.finance.yahoo.com"
        ];
        sec_edgar.hosts = [
          "data.sec.gov"
          "www.sec.gov"
        ];
        fred = {
          hosts = [
            "api.stlouisfed.org"
            "fred.stlouisfed.org"
          ];
          key = "FRED_API_KEY";
        };
        polymarket.hosts = [ "gamma-api.polymarket.com" ];
        alpha_vantage = {
          hosts = [ "www.alphavantage.co" ];
          key = "ALPHA_VANTAGE_API_KEY";
        };
        stocktwits.hosts = [ "api.stocktwits.com" ];
        reddit.hosts = [ "www.reddit.com" ];
      };
      description = "Where TradingAgents reads from (its dataflows/vendors, v0.7.1), for the host's own network; this session's allowlist is closed.";
    };
  };

  config.perSystem =
    { pkgs, config, ... }:
    let
      py = pkgs.python313Packages;
      stockstats = py.buildPythonPackage {
        pname = "stockstats";
        version = "0.6.10";
        pyproject = true;
        src = pkgs.fetchPypi {
          pname = "stockstats";
          version = "0.6.10";
          hash = "sha256-qKjRQF1MkK7fOx+82aIWNxOtla38P/txBbGjklmOTiA=";
        };
        build-system = [
          py.setuptools
          py.setuptools-scm
        ];
        dependencies = [
          py.numpy
          py.pandas
        ];
        doCheck = false;
        pythonImportsCheck = [ "stockstats" ];
      };
      tradingagents = py.buildPythonPackage {
        pname = "tradingagents";
        version = "0.7.1";
        pyproject = true;
        src = inputs.tradingagents;
        build-system = [ py.setuptools ];
        pythonRelaxDeps = true;
        dependencies = with py; [
          cryptography
          langchain-core
          langchain-anthropic
          langchain-google-genai
          langchain-openai
          langgraph
          langgraph-checkpoint-sqlite
          markdown-it-py
          packaging
          pandas
          python-dotenv
          pytz
          questionary
          requests
          rich
          typer
          stockstats
          typing-extensions
          yfinance
        ];
        doCheck = false;
        pythonImportsCheck = [
          "tradingagents"
          "tradingagents.graph.trading_graph"
          "tradingagents.backtest"
        ];
        meta.license = lib.licenses.asl20;
      };
      python = pkgs.python313.withPackages (_: [ tradingagents ]);
      made = builtins.toJSON {
        backendUrl = "https://openrouter.ai/api/v1";
        inherit (cfg)
          deepModel
          quickModel
          debateRounds
          riskRounds
          maxTokens
          dataVendors
          ;
        home = "$HOME/.tradingagents";
      };
      run = pkgs.writeShellApplication {
        name = "research-run";
        runtimeInputs = [ python ];
        text = ''
          # The home is the caller's: its logs, cache and memory stay there.
          RESEARCH_CONFIG=$(jq -c --arg h "''${TRADINGAGENTS_HOME:-$HOME/.tradingagents}" '.home = $h' <<<${lib.escapeShellArg made})
          export RESEARCH_CONFIG
          exec python3 -I ${./_research.py} "$@"
        '';
      };
    in
    {
      packages = {
        inherit tradingagents stockstats;
        research = pkgs.writeShellApplication {
          name = "research";
          runtimeInputs = [
            run
            pkgs.jq
            config.packages.secretspec
            config.packages.pass-cli
          ];
          text = ''
            export PROTON_PASS_KEY_PROVIDER=''${PROTON_PASS_KEY_PROVIDER:-fs}
            exec secretspec run --file ${config.packages.secretspec-toml} --profile research \
              --reason "research $*" -- research-run "$@"
          '';
        };
      };

      # The package imports and its graph builds with nixpkgs' library
      # versions; the signal parser and the sweep's day grid are exercised.
      checks.research-graph =
        pkgs.runCommand "research-graph"
          {
            nativeBuildInputs = [
              python
              pkgs.jq
            ];
          }
          ''
            # The client builds its TLS context at once; the sandbox's
            # SSL_CERT_FILE names nothing.
            export HOME=$TMPDIR OPENAI_API_KEY=unused SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt
            python3 -I - <<'EOF'
            import json, os, sys
            os.environ["RESEARCH_CONFIG"] = ${lib.escapeShellArg made}.replace("$HOME", os.environ["HOME"])
            os.environ["OPENROUTER_API_KEY"] = "unused"
            sys.argv = ["research"]
            sys.path.insert(0, "${./.}")
            import importlib.util
            spec = importlib.util.spec_from_file_location("research", "${./_research.py}")
            r = importlib.util.module_from_spec(spec); spec.loader.exec_module(r)
            cfg = r.config()
            assert cfg["backend_url"] == "https://openrouter.ai/api/v1" and cfg["llm_provider"] == "openai"
            from tradingagents.graph.trading_graph import TradingAgentsGraph
            TradingAgentsGraph(debug=False, config=cfg)
            assert r.signal_of("Final decision: **BUY**") == "BUY"
            assert r.signal_of("sell then hold... HOLD") == "HOLD"
            assert r.signal_of("nothing") == "HOLD"
            days = list(r.trading_days("2026-11-02", "2026-11-08"))
            assert days == ["2026-11-02", "2026-11-03", "2026-11-04", "2026-11-05", "2026-11-06"], days
            print("research-graph: the graph builds on the pinned libraries")
            EOF
            touch $out
          '';
    };
}
