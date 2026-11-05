# The research papers: one per trading strategy, published, and stripped
# of everything that is not the strategy itself (the owner's decision of
# 2026-10-31: income from what runs by itself, algorithmic trading and
# published research). A paper is rendered from the declarations, never
# written against them: the strategy's parameters, the limits (the risk
# policy, public numbers), the Lean theorems and what they guarantee, the
# signal model as the engine describes itself, the backtest method and the
# latest recorded result, and the team's prose under ./_papers.
#
#   research.papers.<strategy> = { title; abstract; authors; sections; prose; public; }
#   research.backtests.<strategy>   the latest backtest record, typed, read
#                                   from ./_json/backtests/<strategy>.json
#                                   when it exists (none yet)
#   research.redaction = { allow; deny; }
#       allow   the fields a paper may show, exact or "prefix.*"; every
#               other input is private, and the renderer never sees it
#       deny    patterns no rendered text may contain (account ids, key
#               prefixes, mailboxes, vault names)
#
#   nix build .#research-papers     papers/<strategy>.{pdf,html,md,typ}
#
# checks.research-papers: Lean (./_lean/Papers.lean) proves the renderer's
# input is exactly the public facts and that every rendered field of every
# declared paper is on the allowlist; then the rendered PDF, HTML and
# sources are scanned for the denylist and the check fails on any hit.
# The prose is `content` (../governance/changes.nix): the research team
# writes and merges it; everything else here is generated.
{ lib, config, ... }:
let
  inherit (lib) mkOption types;
  cfg = config.research;
  inherit (config) trading;
  q = builtins.toJSON;
  date = types.strMatching "[0-9]{4}-[0-9]{2}-[0-9]{2}";
  sectionKinds = [
    "motivation"
    "data"
    "model"
    "algorithm"
    "proofs"
    "backtest"
    "limits"
    "risks"
  ];
  paper = types.submodule (
    { name, ... }:
    {
      options = {
        title = mkOption { type = types.str; };
        abstract = mkOption { type = types.str; };
        authors = mkOption {
          type = types.nonEmptyListOf (types.enum (lib.attrNames config.governance.agents));
          description = "The teams that wrote it (governance.agents).";
        };
        sections = mkOption {
          type = types.nonEmptyListOf (types.enum sectionKinds);
          default = sectionKinds;
          description = "The sections, in order; each has its prose file and its generated part.";
        };
        prose = mkOption {
          type = types.path;
          default = ./_papers + "/${name}";
          description = "The directory of the team's prose, one <section>.md per section (content, ../governance/changes.nix).";
        };
        public = mkOption {
          type = types.bool;
          default = true;
          description = "Rendered and bundled beside the homepage; false keeps it a draft that is built but not bundled.";
        };
      };
    }
  );
  # The latest backtest record of a strategy: the grid it ran over, the
  # result, and the dates. Written under ./_json/backtests by the research
  # team once `research backtest` or the rules' replay has run.
  backtest = types.submodule {
    options = {
      recorded = mkOption {
        type = date;
        description = "The day the record was made.";
      };
      from = mkOption { type = date; };
      to = mkOption { type = date; };
      grid = mkOption {
        type = types.attrsOf (
          types.listOf (
            types.oneOf [
              types.int
              types.float
              types.str
            ]
          )
        );
        description = "What was swept: each parameter and its values (tickers, days, thresholds).";
      };
      benchmark = mkOption {
        type = types.str;
        description = "What alpha is measured against.";
      };
      alpha = mkOption {
        type = types.float;
        description = "Annualised alpha over the benchmark.";
      };
      maxDrawdownPct = mkOption { type = types.numbers.between 0.0 100.0; };
      hitRate = mkOption {
        type = types.numbers.between 0.0 1.0;
        description = "The share of proposals that settled in profit.";
      };
      trades = mkOption { type = types.ints.unsigned; };
    };
  };
  denied = types.submodule {
    options = {
      pattern = mkOption {
        type = types.str;
        description = "An extended regular expression (grep -E).";
      };
      why = mkOption { type = types.str; };
      probe = mkOption {
        type = types.str;
        description = "A stand-in the pattern must catch; the check shows it does before scanning.";
      };
    };
  };

  backtestDir = ./_json/backtests;
  recordedBacktests = lib.filterAttrs (
    s: _: builtins.pathExists (backtestDir + "/${s}.json")
  ) cfg.papers;

  # --- the facts: every input to a paper, as (field, value, public) -----
  allowed =
    field:
    lib.any (
      a: if lib.hasSuffix ".*" a then lib.hasPrefix (lib.removeSuffix "*" a) field else a == field
    ) cfg.redaction.allow;
  fact = field: value: {
    inherit field;
    value = if builtins.isString value then value else q value;
    public = allowed field;
  };
  # The engines describe themselves: a script's module docstring, and the
  # constants of the weather rules, read from the source so a change there
  # is a change here.
  docstringOf = text: lib.elemAt (builtins.split "\"\"\"" text) 2;
  weatherSrc = builtins.readFile ../trading/_weather.py;
  proposeSrc = builtins.readFile ../trading/_propose.py;
  bodyOf =
    fn: src:
    let
      m = builtins.match ".*\ndef ${fn}\\([^\n]*\n(    \"\"\"[^\n]*\n)?    return ([^\n]*)\n.*" src;
    in
    if m == null then
      throw "modules/research/papers.nix: no one-line `return` in _weather.py's ${fn}"
    else
      lib.elemAt m 1;
  weatherCities = lib.concatMap (g: if builtins.isList g then [ (lib.head g) ] else [ ]) (
    builtins.split "\n    \"([A-Za-z ]+)\": \\{\"lat\"" weatherSrc
  );
  weatherQuestions =
    let
      m = builtins.match ".*\nQUESTIONS = \\(([^)]*)\\).*" weatherSrc;
    in
    if m == null then throw "modules/research/papers.nix: no QUESTIONS in _weather.py" else lib.head m;
  leanFiles = {
    Risk = ../trading/_lean/Risk.lean;
    Stages = ../trading/_lean/Stages.lean;
    Papers = ./_lean/Papers.lean;
  };
  sourceKey = lib.replaceStrings [ "-" ] [ "_" ];
  hostsOf = key: lib.concatStringsSep " " cfg.dataSources.${key}.hosts;

  factsOf =
    name: p:
    let
      s = trading.strategies.${name};
      b = trading.backends.${s.backend};
      l = trading.limits.${s.backend} or null;
      bt = cfg.backtests.${name} or null;
      sub =
        prefix: attrs:
        lib.mapAttrsToList (k: v: fact "${prefix}.${k}" v) (lib.filterAttrs (_: v: v != null) attrs);
    in
    [
      (fact "paper.strategy" name)
      (fact "paper.title" p.title)
      (fact "paper.abstract" p.abstract)
      (fact "paper.authors" (lib.concatStringsSep ", " p.authors))
      (fact "paper.sections" (lib.concatStringsSep ", " p.sections))
      (fact "paper.stage" s.stage)
    ]
    ++ map (k: fact "prose.${k}" (builtins.readFile (p.prose + "/${k}.md"))) p.sections
    ++ sub "strategy" {
      inherit (s)
        kind
        symbol
        bar
        backend
        startingUsd
        decisions
        ;
    }
    ++ lib.optionals (s.event != null) (sub "strategy.event" s.event)
    ++ lib.optionals (s.option != null) (sub "strategy.option" s.option)
    ++ lib.optionals (s.params != null) (sub "strategy.params" s.params)
    ++ sub "backend" { inherit (b) account adapter; }
    ++ lib.optionals (l != null) (sub "limits" l)
    ++ sub "promotion" {
      backtested = s.promotion.backtest != null;
      paperDays = if s.promotion.paper == null then 0 else s.promotion.paper.days;
      decided = s.promotion.live != null;
    }
    ++ lib.optionals (s.kind == "event-rule") [
      (fact "data.source.${s.event.source}" (hostsOf (sourceKey s.event.source)))
      (fact "signal.doc" (docstringOf weatherSrc))
      (fact "signal.sigmaF" (bodyOf "sigma_f" weatherSrc))
      (fact "signal.precipSd" (bodyOf "forecast_precip_sd" weatherSrc))
      (fact "signal.questions" weatherQuestions)
      (fact "signal.cities" (lib.concatStringsSep ", " weatherCities))
    ]
    ++ lib.optionals (s.kind == "agent-option") (
      map (v: fact "data.source.${v}" (hostsOf v)) (
        lib.unique (lib.concatMap (lib.splitString ",") (lib.attrValues cfg.dataVendors))
      )
      ++ sub "research" {
        inherit (cfg)
          deepModel
          quickModel
          debateRounds
          riskRounds
          maxTokens
          ;
        dataVendors = lib.concatStringsSep ", " (lib.mapAttrsToList (k: v: "${k}: ${v}") cfg.dataVendors);
        keyName = config.governance.agents.${lib.head p.authors}.key;
      }
    )
    ++ [ (fact "algorithm.doc" (docstringOf proposeSrc)) ]
    ++ lib.mapAttrsToList (n: f: fact "lean.${n}" (builtins.readFile f)) leanFiles
    ++ (
      if bt == null then
        [ (fact "backtest.status" "none") ]
      else
        sub "backtest" (bt // { status = "recorded"; })
    );

  facts = lib.mapAttrs factsOf cfg.papers;
  publicOf = fs: map (f: { inherit (f) field value; }) (lib.filter (f: f.public) fs);
  allowedExact = lib.unique (
    lib.filter allowed (lib.concatMap (fs: map (f: f.field) fs) (lib.attrValues facts))
  );

  problems =
    lib.concatLists (
      lib.mapAttrsToList (
        n: p:
        lib.optional (!(trading.strategies ? ${n})) "research.papers.${n}: no trading.strategies.${n}"
        ++ map (k: "research.papers.${n}: no prose ${toString p.prose}/${k}.md") (
          lib.filter (k: !builtins.pathExists (p.prose + "/${k}.md")) p.sections
        )
      ) cfg.papers
    )
    ++ lib.optional (lib.any (
      d: lib.hasInfix "\n" d.pattern
    ) cfg.redaction.deny) "research.redaction.deny: a pattern holds a newline";
  checked = builtins.seq (lib.assertMsg (problems == [ ]) (lib.concatStringsSep "\n" problems));

  rendered = ''
    namespace Kagamizo.Papers

    /-- The fields a paper may show, rendered by modules/research/papers.nix
    from research.redaction.allow. -/
    def allowed : List String := [
    ${lib.concatMapStringsSep ",\n" (f: "  ${q f}") allowedExact}
    ]

    /-- Every paper's inputs, rendered by modules/research/papers.nix. -/
    def declared : List (String × List Fact) := [
    ${lib.concatStringsSep ",\n" (
      lib.mapAttrsToList (
        n: fs:
        "  (${q n}, [\n${
            lib.concatMapStringsSep ",\n" (
              f: "    { field := ${q f.field}, value := ${q f.value}, published := ${lib.boolToString f.public} }"
            ) fs
          }\n  ])"
      ) facts
    )}
    ]

    /-- A fact is public exactly when its field is allowed: the rendering
    agrees with the allowlist. -/
    theorem declared_public_is_allowed :
        declared.all (fun p => p.2.all fun f => f.published == allowed.contains f.field) = true := by
      decide

    /-- So every rendered field of every declared paper is allowed. -/
    theorem declared_rendered_allowed : ∀ p ∈ declared, ∀ f ∈ render p.2, f.field ∈ allowed := by
      intro p hp
      exact render_fields_allowed allowed p.2 (List.all_eq_true.mp declared_public_is_allowed p hp)

    /-- The redaction does work: every paper has inputs it never shows. -/
    theorem every_paper_redacts : declared.all (fun p => p.2.any fun f => !f.published) = true := by
      decide

    end Kagamizo.Papers
  '';
in
{
  options.research = {
    papers = mkOption {
      type = types.attrsOf paper;
      default = { };
    };
    backtests = mkOption {
      type = types.attrsOf backtest;
      readOnly = true;
      description = "The latest recorded backtest of each paper's strategy (./_json/backtests/<strategy>.json), typed.";
    };
    redaction = {
      allow = mkOption {
        type = types.listOf (types.strMatching "[a-zA-Z0-9_.-]+(\\.\\*)?");
        description = "The fields a paper may show: exact, or a prefix as `prefix.*`.";
      };
      deny = mkOption { type = types.listOf denied; };
    };
  };

  config = {
    research = {
      backtests = lib.mapAttrs (s: _: lib.importJSON (backtestDir + "/${s}.json")) recordedBacktests;

      redaction = {
        allow = [
          "paper.*"
          "prose.*"
          # The strategy as declared, but never where its decisions and
          # records live on the host.
          "strategy.kind"
          "strategy.symbol"
          "strategy.bar"
          "strategy.backend"
          "strategy.startingUsd"
          "strategy.event.*"
          "strategy.option.*"
          "strategy.params.*"
          # The adapter is ours and public; the account it reaches is not.
          "backend.adapter"
          # The limits are the risk policy, and the stage its evidence.
          "limits.*"
          "promotion.*"
          "data.*"
          "signal.*"
          # The research loop's shape and open-weight models; never its key.
          "research.deepModel"
          "research.quickModel"
          "research.debateRounds"
          "research.riskRounds"
          "research.maxTokens"
          "research.dataVendors"
          "algorithm.*"
          "lean.*"
          "backtest.*"
        ];
        deny = [
          {
            pattern = "[0-9][A-Z]{2}[0-9]{5}";
            why = "an account id";
            probe = "1AB12345";
          }
          {
            pattern = "sk-or-";
            why = "an OpenRouter key";
            probe = "sk-or-v1-x";
          }
          {
            pattern = "@mirazo\\.org|@jingzo\\.org";
            why = "a mailbox";
            probe = "x@jingzo.org";
          }
          {
            pattern = "Kagamizo-|Jingzo-|Mirazo-";
            why = "a vault or item name";
            probe = "Kagamizo-infra";
          }
        ];
      };

      papers = {
        weather-rules = {
          title = "Deterministic Weather Rules for Event Contracts";
          abstract = "A rule-based pricing of Kalshi's weather contracts as listed on Public: each contract's question is parsed into a typed band on a city's monthly precipitation or a day's high temperature, a forecast is turned into a normal distribution whose spread grows with the lead, and the contract is bought when the model's probability exceeds its price by a declared edge. Every proposal is held to a risk rule whose guarantees are proven in Lean; the strategy is at the research stage, and no backtest is recorded yet.";
          authors = [ "research-jingzo" ];
        };
        spy-agents = {
          title = "A Multi-Agent Daily Decision on SPY, Expressed as One Defined-Risk Option";
          abstract = "The TradingAgents framework (analysts, a bull and bear debate, a trader, a risk discussion and a portfolio manager, on open-weight models) is run once a day on SPY and its decision, BUY, SELL or HOLD, is expressed as at most one long call or put chosen by rule from the chain: the nearest expiration in a declared window, the cheapest contract within a premium cap at a minimum absolute delta. The worst case of every proposal is its premium, bounded by limits whose guarantees are proven in Lean; the strategy is at the research stage, and no backtest is recorded yet.";
          authors = [ "research-jingzo" ];
        };
      };
    };

    perSystem =
      { pkgs, ... }:
      let
        publicJson = lib.mapAttrs (
          n: fs:
          pkgs.writeText "${n}-public.json" (q {
            strategy = n;
            facts = publicOf fs;
          })
        ) facts;
        papers =
          pkgs.runCommand "research-papers"
            {
              nativeBuildInputs = [
                pkgs.python313
                pkgs.pandoc
                pkgs.typst
              ];
            }
            (checked ''
              mkdir -p $out/papers
              export HOME=$TMPDIR
              ${lib.concatStringsSep "\n" (
                lib.mapAttrsToList (n: f: ''
                  python3 -I ${./_paper.py} ${f} $out/papers/${n}.md
                  pandoc $out/papers/${n}.md -s -t typst -V mainfont="Libertinus Serif" -V monofont="DejaVu Sans Mono" -o $out/papers/${n}.typ
                  typst compile --ignore-system-fonts $out/papers/${n}.typ $out/papers/${n}.pdf
                  pandoc $out/papers/${n}.md -s --mathml --metadata lang=en -t html5 -o $out/papers/${n}.html
                '') publicJson
              )}
              echo ${
                lib.escapeShellArg (q (lib.attrNames (lib.filterAttrs (_: p: p.public) cfg.papers)))
              } > $out/papers/public.json
            '');
        denyFile = pkgs.writeText "deny.txt" (
          lib.concatMapStrings (d: "${d.pattern}\n") cfg.redaction.deny
        );
      in
      {
        packages.research-papers = papers;

        checks.research-papers =
          pkgs.runCommand "research-papers"
            {
              nativeBuildInputs = [
                pkgs.lean4
                pkgs.poppler-utils
              ];
              facts = rendered;
              passAsFile = [ "facts" ];
            }
            ''
              cat ${./_lean/Papers.lean} "$factsPath" > Check.lean
              lean Check.lean

              # The scan: nothing rendered carries a denied pattern. The
              # patterns are first shown to catch what they are for.
              ${lib.concatMapStrings (d: ''
                printf '%s\n' ${lib.escapeShellArg d.probe} | grep -qE ${lib.escapeShellArg d.pattern} \
                  || { echo "research.redaction.deny: ${d.why}: the pattern misses its probe" >&2; exit 1; }
              '') cfg.redaction.deny}
              mkdir text
              for pdf in ${papers}/papers/*.pdf; do
                pdftotext "$pdf" "text/$(basename "$pdf" .pdf).txt"
                test -s "text/$(basename "$pdf" .pdf).txt"
              done
              cp ${papers}/papers/*.md ${papers}/papers/*.typ ${papers}/papers/*.html text/
              if grep -rEnf ${denyFile} text; then
                echo "research-papers: a rendered paper carries a denied pattern" >&2
                exit 1
              fi
              ${lib.concatMapStrings (n: ''
                test -s ${papers}/papers/${n}.pdf
                test -s ${papers}/papers/${n}.html
              '') (lib.attrNames cfg.papers)}
              cp -r text $out
            '';
      };
  };
}
