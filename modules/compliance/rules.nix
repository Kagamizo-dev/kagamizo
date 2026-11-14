# The rules the owner's trading and the business are held to, typed with
# their sources and checked against the repository's own declarations: a
# strategy, a limit or an account that would break one fails evaluation.
#
#   compliance.rules.<id> = {
#     authority;    # finra | sec | fed | irs | cftc | public | state
#     citation; title; summary;
#     source;       # the page that states it; `more` for the pages beside it
#     checked;      # the day the source was read, or null: not read, and
#                   # the summary says so
#     applies = { entities; accounts; instruments; };
#     constraint;   # "informational", or one typed, machine-checked statement:
#                   #   pdt = { equityUsd; maxDayTradesPer5Days; }
#                   #     FINRA's pattern-day-trader rule; Lean holds every
#                   #     strategy to it on the account it runs on
#                   #   options-level = { kinds.<trade kind> = <level>; }
#                   #     the level each trade kind needs (../trading/limits.nix's
#                   #     kinds); every allowed kind must have one, and Lean
#                   #     holds every paper or live strategy to its level
#                   #   exchange = { symbol; }
#                   #     event contracts are this exchange's and no other's
#                   #   obligation = { form; }
#                   #     the tax form money.obligations lists for the entity
#   }
#   compliance.observed.<account> = { brokerageId; margin; optionsLevel;
#                                     equityUsd; observed; by; others; }
#       what the account's API showed on a day: the facts the rules are
#       decided against, never assumed
#   compliance.taxYear      the year whose obligations the rules are tied to
#
# checks.compliance-rules (./_lean/Rules.lean): Lean proves what pdtSafe and
# optionsLevelOk guarantee and decides them over the observed accounts and
# the declared strategies. packages.compliance-index prints the rules as a
# Markdown table (`--json` for JSON); the homepage shows them (../site).
#
# No state item: the owner's state of residence is not named in the repo
# (money.tax.mirazo) and neither Texas nor Wyoming taxes personal income or
# licenses a person trading their own money; the Wyoming LLC's annual
# report is money's (../money/_obligations.nix), not a trading rule.
{ lib, config, ... }:
let
  inherit (lib) mkOption types;
  cfg = config.compliance;
  q = builtins.toJSON;
  date = types.strMatching "[0-9]{4}-[0-9]{2}-[0-9]{2}";
  url = types.strMatching "https://.+";
  held = config.accounts.held;
  entities = lib.attrNames config.identity.checked.entities;
  inherit (config) trading;
  instruments = [
    "equity"
    "option"
    "event-contract"
    "crypto"
    "bond"
  ];
  # The kinds a trade may be (../trading/limits.nix) and, per strategy
  # kind, the ones it proposes (../trading/_propose.py: KINDS, EVENT_KINDS).
  tradeKinds = [
    "long-call"
    "long-put"
    "debit-spread"
    "event-yes"
    "event-no"
    "crypto-long"
  ];
  proposes = {
    ema-cross = [ ];
    agent-option = [
      "long-call"
      "long-put"
    ];
    event-rule = [
      "event-yes"
      "event-no"
    ];
    agent-crypto = [ "crypto-long" ];
  };
  instrumentOf = {
    ema-cross = "equity";
    agent-option = "option";
    event-rule = "event-contract";
    agent-crypto = "crypto";
  };
  leanInstrument = lib.replaceStrings [ "event-contract" ] [ "eventContract" ];

  constraint = types.either (types.enum [ "informational" ]) (
    types.attrTag {
      pdt = mkOption {
        type = types.submodule {
          options = {
            equityUsd = mkOption { type = types.ints.positive; };
            maxDayTradesPer5Days = mkOption { type = types.ints.unsigned; };
          };
        };
        description = "A margin account under equityUsd may make at most maxDayTradesPer5Days day trades in five business days.";
      };
      options-level = mkOption {
        type = types.submodule {
          options.kinds = mkOption {
            type = types.attrsOf (types.ints.between 0 6);
            description = "The level each trade kind needs; 0 for a kind that is no option.";
          };
        };
        description = "The options level each trade kind needs, as the broker grants them.";
      };
      exchange = mkOption {
        type = types.submodule {
          options.symbol = mkOption { type = types.strMatching "[A-Z][A-Z0-9.]*"; };
        };
        description = "Event contracts are this exchange's: every event-rule strategy's symbol.";
      };
      obligation = mkOption {
        type = types.submodule {
          options.form = mkOption {
            type = types.str;
            description = "A form money.obligations lists for the entity, by its exact name.";
          };
        };
        description = "A tax form the rule makes due, tied to money.obligations.";
      };
    }
  );

  rule = types.submodule {
    options = {
      authority = mkOption {
        type = types.enum [
          "finra"
          "sec"
          "fed"
          "irs"
          "cftc"
          "public"
          "state"
        ];
      };
      citation = mkOption { type = types.str; };
      title = mkOption { type = types.str; };
      summary = mkOption { type = types.str; };
      source = mkOption {
        type = url;
        description = "The page that states it.";
      };
      more = mkOption {
        type = types.listOf url;
        default = [ ];
        description = "Pages beside the source: the investor page, the form, the exchange's own.";
      };
      checked = mkOption {
        type = types.nullOr date;
        description = "When the source was read; null when it was not, and the summary says so.";
      };
      applies = {
        entities = mkOption {
          type = types.listOf (types.enum entities);
          default = [ ];
        };
        accounts = mkOption {
          type = types.listOf (types.enum (lib.attrNames held));
          default = [ ];
        };
        instruments = mkOption {
          type = types.listOf (types.enum instruments);
          default = [ ];
        };
      };
      constraint = mkOption {
        type = constraint;
        default = "informational";
      };
    };
  };

  observed = types.submodule {
    options = {
      brokerageId = mkOption {
        type = types.strMatching "[A-Z0-9]{8}";
        description = "The brokerage account the strategies trade on, as `accounts list` names it.";
      };
      margin = mkOption { type = types.bool; };
      optionsLevel = mkOption {
        type = types.ints.between 0 6;
        description = "0 when the account has no options approval.";
      };
      equityUsd = mkOption {
        type = types.ints.unsigned;
        description = "Cash and securities, in whole dollars, as read; rounded down.";
      };
      observed = mkOption { type = date; };
      by = mkOption {
        type = types.str;
        description = "What read it: a command of ours, never a screenshot.";
      };
      others = mkOption {
        type = types.attrsOf (
          types.submodule {
            options = {
              brokerageId = mkOption { type = types.strMatching "[A-Z0-9]{8}"; };
              margin = mkOption { type = types.bool; };
              note = mkOption { type = types.str; };
            };
          }
        );
        default = { };
        description = "The login's other accounts, which no strategy trades on.";
      };
    };
  };

  # The constraint as one line, for the index and the homepage.
  constraintText =
    c:
    if c == "informational" then
      "informational"
    else if c ? pdt then
      "pdt: a margin account under \$${toString c.pdt.equityUsd} makes at most ${toString c.pdt.maxDayTradesPer5Days} day trades in 5 business days"
    else if c ? options-level then
      "options level: ${
        lib.concatStringsSep ", " (lib.mapAttrsToList (k: l: "${k} ${toString l}") c.options-level.kinds)
      }"
    else if c ? exchange then
      "exchange: every event contract is ${c.exchange.symbol}'s"
    else
      "obligation: ${c.obligation.form} (money.obligations)";
  appliesText =
    a:
    lib.concatStringsSep "; " (
      lib.filter (s: s != "") [
        (lib.concatStringsSep ", " a.entities)
        (lib.concatStringsSep ", " a.accounts)
        (lib.concatStringsSep ", " a.instruments)
      ]
    );
  byId = lib.mapAttrsToList (id: r: r // { inherit id; }) cfg.rules;
  withConstraint = tag: lib.filter (r: r.constraint != "informational" && r.constraint ? ${tag}) byId;

  # Each strategy with the account it runs on, as observed, and what it needs.
  strategies = lib.mapAttrsToList (
    name: s:
    let
      account = trading.backends.${s.backend}.account;
      levelRules = lib.filter (r: lib.elem account r.applies.accounts) (withConstraint "options-level");
      levelOf = k: lib.foldl' lib.max 0 (map (r: r.constraint.options-level.kinds.${k} or 0) levelRules);
    in
    {
      inherit name account;
      inherit (s)
        stage
        maxDayTradesPer5Days
        kind
        symbol
        ;
      instrument = instrumentOf.${s.kind};
      needsOptionsLevel = lib.foldl' lib.max 0 (map levelOf proposes.${s.kind});
    }
  ) trading.strategies;

  obligations = config.money.obligations cfg.taxYear;
  problems =
    # Every account a strategy runs on was observed.
    lib.concatMap (
      s:
      lib.optional (!(cfg.observed ? ${s.account}))
        "trading.strategies.${s.name} runs on ${s.account}: declare compliance.observed.${s.account} from a read of its API"
    ) strategies
    # Every trade kind a backend allows has an options level stated by a
    # rule that applies to its account, so nothing trades a kind whose
    # approval is unknown.
    ++ lib.concatLists (
      lib.mapAttrsToList (
        backend: l:
        let
          account = trading.backends.${backend}.account;
          stated = lib.concatMap (r: lib.attrNames r.constraint.options-level.kinds) (
            lib.filter (r: lib.elem account r.applies.accounts) (withConstraint "options-level")
          );
        in
        map (
          k:
          "trading.limits.${backend} allows ${k}, but no compliance rule applying to ${account} states its options level"
        ) (lib.subtractLists stated l.allowed)
      ) trading.limits
    )
    # A rule's options-level kinds are trade kinds.
    ++ lib.concatMap (
      r:
      map (
        k: "compliance.rules.${r.id}: ${k} is not a trade kind (${lib.concatStringsSep ", " tradeKinds})"
      ) (lib.subtractLists tradeKinds (lib.attrNames r.constraint.options-level.kinds))
    ) (withConstraint "options-level")
    # Event contracts are the declared exchange's.
    ++ lib.concatMap (
      r:
      lib.concatMap (
        s:
        lib.optional
          (
            s.instrument == "event-contract"
            && lib.elem s.account r.applies.accounts
            && s.symbol != r.constraint.exchange.symbol
          )
          "trading.strategies.${s.name}: event contracts on ${s.account} are ${r.constraint.exchange.symbol}'s (compliance.rules.${r.id}), not ${s.symbol}"
      ) strategies
    ) (withConstraint "exchange")
    # A form a rule makes due is one money.obligations lists for an entity it applies to.
    ++ lib.concatMap (
      r:
      lib.optional
        (
          !lib.any (
            o: o.form == r.constraint.obligation.form && lib.elem o.entity r.applies.entities
          ) obligations
        )
        "compliance.rules.${r.id}: money.obligations ${toString cfg.taxYear} lists no ${q r.constraint.obligation.form} for ${lib.concatStringsSep ", " r.applies.entities}"
    ) (withConstraint "obligation")
    ++ lib.concatMap (
      r:
      lib.optional (
        r.checked == null && !lib.hasInfix "not read" r.summary
      ) "compliance.rules.${r.id}: checked is null, so the summary must say the source was not read"
    ) byId;

  rendered = ''
    namespace Kagamizo.Compliance

    /-- Every strategy with the account it runs on, as observed
    (compliance.observed) and declared (trading.strategies), rendered by
    modules/compliance/rules.nix. -/
    def pairs : List (Account × Strategy) := [
    ${lib.concatMapStringsSep ",\n" (
      s:
      let
        a = cfg.observed.${s.account};
      in
      "  ({ name := ${q s.account}, margin := ${lib.boolToString a.margin}, equityUsd := ${toString a.equityUsd}, optionsLevel := ${toString a.optionsLevel} },\n"
      + "   { name := ${q s.name}, instrument := .${leanInstrument s.instrument}, maxDayTradesPer5Days := ${toString s.maxDayTradesPer5Days}, needsOptionsLevel := ${toString s.needsOptionsLevel}, stage := .${s.stage} })"
    ) strategies}
    ]

    /-- No strategy makes its account a pattern day trader. -/
    theorem all_pdt_safe : pairs.all (fun p => pdtSafe p.1 p.2) = true := by decide +kernel

    /-- Every strategy that sends orders to the broker has its options level. -/
    theorem all_levels_ok : pairs.all (fun p => optionsLevelOk p.1 p.2) = true := by decide +kernel

    ${lib.concatMapStringsSep "\n" (r: ''
      /-- The rule's numbers (compliance.rules.${r.id}) are Lean's. -/
      example : pdtEquityUsd = ${toString r.constraint.pdt.equityUsd} := rfl
      example : pdtMaxDayTrades = ${toString r.constraint.pdt.maxDayTradesPer5Days} := rfl
    '') (withConstraint "pdt")}
    end Kagamizo.Compliance
  '';

  indexJson = builtins.toJSON (
    lib.mapAttrs (
      _: r:
      r
      // {
        constraintText = constraintText r.constraint;
      }
    ) cfg.rules
  );
  indexMd = ''
    | Authority | Citation | Title | Applies | Constraint | Source | Checked |
    |---|---|---|---|---|---|---|
    ${lib.concatMapStrings (
      r:
      "| ${r.authority} | ${r.citation} | ${r.title} | ${appliesText r.applies} | ${constraintText r.constraint} | ${r.source} | ${
        if r.checked == null then "not read" else r.checked
      } |\n"
    ) byId}
  '';
in
{
  options.compliance = {
    rules = mkOption {
      type = types.attrsOf rule;
      default = { };
    };
    observed = mkOption {
      type = types.attrsOf observed;
      default = { };
      description = "Per held brokerage account, what its API showed.";
    };
    taxYear = mkOption {
      type = types.ints.positive;
      default = 2026;
    };
    index = {
      json = mkOption {
        type = types.str;
        readOnly = true;
        default = indexJson;
      };
      markdown = mkOption {
        type = types.str;
        readOnly = true;
        default = indexMd;
      };
      rows = mkOption {
        type = types.listOf types.attrs;
        readOnly = true;
        default = map (
          r:
          r
          // {
            applies = appliesText r.applies;
            constraint = constraintText r.constraint;
          }
        ) byId;
        description = "Every rule as one row, for the homepage (../site).";
      };
    };
  };

  config = {
    # Read through `brokerage summary` (accounts list) on 2026-11-04: the
    # brokerage account is a margin account at options level 1, with $0.00
    # cash and no positions (the $100 seed is not deposited yet; either way
    # far under $25,000); the Roth IRA is a cash account; the entity account
    # is a margin account with no options approval.
    compliance.observed = {
      public-mirazo = {
        brokerageId = "5OI41709";
        margin = true;
        optionsLevel = 1;
        equityUsd = 0;
        observed = "2026-11-04";
        by = "brokerage summary (accounts list, portfolio show)";
        others.roth-ira = {
          brokerageId = "5OD75475";
          margin = false;
          note = "the Roth IRA, a cash account: no strategy trades on it";
        };
      };
      public-jingzo = {
        brokerageId = "2OP05949";
        margin = true;
        optionsLevel = 0;
        equityUsd = 0;
        observed = "2026-11-04";
        by = "brokerage summary, listed beside the personal accounts (QSearch LLC's entity account; no options)";
      };
    };

    compliance.rules = {
      finra-4210-pdt = {
        authority = "finra";
        citation = "FINRA Rule 4210(f)(8)(B)";
        title = "Pattern day trader";
        summary = ''
          A customer who makes four or more day trades (a buy and a sell of
          the same security on one business day) within five business days
          in a margin account is a pattern day trader, unless those trades
          are 6% or less of the account's trades in the period. A pattern
          day trader must hold $25,000 of equity in the account; under it,
          day trading is restricted (Public: sell-only for 90 days after the
          next day trade). The rule applies to the margin accounts only;
          every strategy declares its cadence (trading.strategies.<s>.
          maxDayTradesPer5Days) and Lean holds it under four.
        '';
        source = "https://www.finra.org/rules-guidance/rulebooks/finra-rules/4210";
        more = [ "https://www.finra.org/investors/insights/day-trading-margin-requirements-know-rules" ];
        checked = "2026-11-04";
        applies = {
          entities = [
            "mirazo"
            "jingzo"
          ];
          accounts = [
            "public-mirazo"
            "public-jingzo"
          ];
          instruments = [
            "equity"
            "option"
          ];
        };
        constraint.pdt = {
          equityUsd = 25000;
          maxDayTradesPer5Days = 3;
        };
      };

      public-day-trading = {
        authority = "public";
        citation = "Open to the Public Investing, Day Trading Risk Disclosure";
        title = "Public's day-trading disclosure";
        summary = ''
          Public's statement of the rule for its margin accounts, read
          2026-11-04: four or more day trades in five consecutive business
          days flags the account a pattern day trader; it must then close
          each business day with at least $25,000 in cash and securities
          (Treasury bills, crypto and alternative assets excluded), or the
          next day trade restricts it to sell-only for 90 days from the
          last day trade. Restates FINRA 4210(f)(8)(B), which carries the
          typed constraint.
        '';
        source = "https://public.com/disclosures/day-trading-risk-disclosures";
        checked = "2026-11-04";
        applies = {
          entities = [
            "mirazo"
            "jingzo"
          ];
          accounts = [
            "public-mirazo"
            "public-jingzo"
          ];
          instruments = [
            "equity"
            "option"
          ];
        };
      };

      fed-reg-t = {
        authority = "fed";
        citation = "12 CFR Part 220 (Regulation T), §220.4 margin account, §220.12 supplement; FINRA Rule 4210(c) maintenance";
        title = "Margin: initial and maintenance requirements";
        summary = ''
          A broker may lend at most 50% of the value of margin equity
          securities at purchase (Regulation T's supplement); FINRA Rule
          4210(c) requires 25% maintenance equity on long positions, and the
          broker's house requirement may be higher and change without
          notice (Public's margin disclosure statement). A long option and
          a bought event contract are paid in full: nothing here borrows,
          and the limits (trading.limits) keep every order within the
          seed, so no maintenance call can arise from the strategies.
        '';
        source = "https://www.ecfr.gov/current/title-12/chapter-II/subchapter-A/part-220";
        more = [
          "https://www.finra.org/rules-guidance/rulebooks/finra-rules/4210"
          "https://public.com/disclosures/margin-disclosure-statement"
        ];
        checked = "2026-11-04";
        applies = {
          entities = [
            "mirazo"
            "jingzo"
          ];
          accounts = [
            "public-mirazo"
            "public-jingzo"
          ];
          instruments = [
            "equity"
            "option"
          ];
        };
      };

      public-margin-agreement = {
        authority = "public";
        citation = "Apex Clearing Customer Margin & Short Account Agreement, via Public (cites FINRA Rule 4210(f)(5))";
        title = "The margin agreement";
        summary = ''
          Both Public accounts are margin accounts, so this agreement with
          Apex Clearing (Public's clearing firm) is in force on each: Apex
          may lend against the securities, raise its requirements, and
          liquidate to meet a call without notice; margin is maintained on
          the net of consolidated accounts (FINRA 4210(f)(5)). Read
          2026-11-04. The business borrows nothing (fed-reg-t).
        '';
        source = "https://public.com/disclosures/apex-margin-agreement";
        more = [ "https://public.com/disclosures/margin-disclosure-statement" ];
        checked = "2026-11-04";
        applies = {
          entities = [
            "mirazo"
            "jingzo"
          ];
          accounts = [
            "public-mirazo"
            "public-jingzo"
          ];
          instruments = [
            "equity"
            "option"
          ];
        };
      };

      finra-2360-options = {
        authority = "finra";
        citation = "FINRA Rule 2360(b)(16) account approval, 2360(b)(11)(A)(1) the options disclosure document";
        title = "Options accounts";
        summary = ''
          A member may accept an option order only in an account it has
          approved for options, after collecting the customer's financial
          and investment information and deciding what strategies the
          account may carry; the OCC's Characteristics and Risks of
          Standardized Options is delivered at or before approval. The
          levels Public grants are the next rule's.
        '';
        source = "https://www.finra.org/rules-guidance/rulebooks/finra-rules/2360";
        more = [
          "https://www.theocc.com/company-information/documents-and-archives/options-disclosure-document"
        ];
        checked = "2026-11-04";
        applies = {
          entities = [
            "mirazo"
            "jingzo"
          ];
          accounts = [
            "public-mirazo"
            "public-jingzo"
          ];
          instruments = [ "option" ];
        };
      };

      public-options-levels = {
        authority = "public";
        citation = "Apex Clearing Option Agreement, Level / Strategy table (69183P-OPTA 01/30/2026), via Public";
        title = "Options levels as Public grants them";
        summary = ''
          Level 1: covered calls, buy-writes, covered-call rolls, married
          puts. Level 2: long calls, long puts, covered puts, long straddles
          and strangles. Level 3: equity debit, credit and calendar spreads.
          Level 4: index spreads. Level 5: naked equity puts. Level 6: naked
          calls and naked index puts. The brokerage account 5OI41709 is at
          level 1 (compliance.observed), so the long calls and puts of
          spy-agents need the owner's raise to level 2 before its paper
          stage; a debit spread (allowed in trading.limits, proposed by
          nothing yet) would need level 3. An event contract is no option:
          level 0. Public's own page lists the same strategies without the
          numbers.
        '';
        source = "https://public.com/disclosures/apex-option-agreement";
        more = [ "https://public.com/invest/options-trading" ];
        checked = "2026-11-04";
        applies = {
          entities = [
            "mirazo"
            "jingzo"
          ];
          accounts = [
            "public-mirazo"
            "public-jingzo"
          ];
          instruments = [
            "option"
            "event-contract"
          ];
        };
        constraint.options-level.kinds = {
          long-call = 2;
          long-put = 2;
          debit-spread = 3;
          event-yes = 0;
          event-no = 0;
          crypto-long = 0;
        };
      };

      finra-2090-kyc = {
        authority = "finra";
        citation = "FINRA Rule 2090 (Know Your Customer), Rule 2111 (Suitability); 31 CFR 1023.220 (customer identification)";
        title = "Know your customer";
        summary = ''
          The broker verifies who opens the account and keeps the facts it
          needs to serve it; a recommendation must suit the customer (the
          strategies take none). Opening an account is the owner's signup
          step (their decision of 2026-10-24); Public's event-contracts
          agreement reserves the right to ask for identity documents at any
          time, and a profile change (the pending move of Public's login to
          finance@mirazo.org) is a page in Public's app.
        '';
        source = "https://www.finra.org/rules-guidance/rulebooks/finra-rules/2090";
        more = [ "https://public.com/disclosures/eventcontractscustomeragreement" ];
        checked = "2026-11-04";
        applies = {
          entities = [
            "mirazo"
            "jingzo"
          ];
          accounts = [
            "public-mirazo"
            "public-jingzo"
            "ibkr-jingzo"
          ];
        };
      };

      sec-15c3-3 = {
        authority = "sec";
        citation = "17 CFR 240.15c3-3 (the customer protection rule); SIPC";
        title = "Customer protection";
        summary = ''
          The broker-dealer keeps customers' fully paid and excess margin
          securities in its possession or control and a reserve of
          customers' cash; SIPC covers up to $500,000 of securities and cash
          if it fails. Event contracts are not securities: they sit in a
          separate event-contracts account under CFTC Regulation 22 (cleared
          swaps customer collateral), outside SIPC (Public's risk
          disclosure). Nothing in the repo relies on either.
        '';
        source = "https://www.law.cornell.edu/cfr/text/17/240.15c3-3";
        more = [ "https://public.com/disclosures/eventcontractsrisk" ];
        checked = "2026-11-04";
        applies = {
          entities = [
            "mirazo"
            "jingzo"
          ];
          accounts = [
            "public-mirazo"
            "public-jingzo"
          ];
          instruments = [
            "equity"
            "option"
            "event-contract"
          ];
        };
      };

      sec-advisers-act = {
        authority = "sec";
        citation = "Investment Advisers Act §202(a)(11), 15 U.S.C. §80b-2(a)(11), and its publisher's exclusion (D)";
        title = "Own money only: no advisory business";
        summary = ''
          An investment adviser is one who, for compensation, advises others
          about securities; the business advises no one and holds no
          client money (the owner's decision of 2026-10-31: nothing sold by
          appointment, no client contracts), and its published research is
          a bona fide publication of general circulation, which the Act
          excludes. So no adviser or broker registration; a change that
          took clients would be a change to this rule first.
        '';
        source = "https://www.law.cornell.edu/uscode/text/15/80b-2";
        checked = "2026-11-04";
        applies = {
          entities = [
            "mirazo"
            "jingzo"
            "kagamizo"
          ];
        };
      };

      irs-1091-wash-sales = {
        authority = "irs";
        citation = "26 U.S.C. §1091; Publication 550, Wash Sales";
        title = "Wash sales";
        summary = ''
          A loss on a sale of stock or securities (options included) is
          disallowed when substantially identical ones are bought within
          30 days before or after; the loss is added to the new lot's
          basis. The broker's 1099-B reports wash sales within one account
          for identical CUSIPs only; across the brokerage account, the Roth
          IRA and IBKR, the taxpayer tracks them. Section 1256 contracts
          are outside §1091. Reported on Form 8949 (money.obligations).
        '';
        source = "https://www.law.cornell.edu/uscode/text/26/1091";
        more = [ "https://www.irs.gov/publications/p550" ];
        checked = "2026-11-04";
        applies = {
          entities = [
            "mirazo"
            "jingzo"
          ];
          accounts = [
            "public-mirazo"
            "public-jingzo"
            "ibkr-jingzo"
          ];
          instruments = [
            "equity"
            "option"
          ];
        };
        constraint.obligation.form = "Form 8949, Schedule D";
      };

      irs-8949-reporting = {
        authority = "irs";
        citation = "Form 8949 and Schedule D (Form 1040)";
        title = "Reporting every sale";
        summary = ''
          Every sale of a security or option closed in the year is listed on
          Form 8949, carried to Schedule D, from the broker's 1099-B; QSearch
          LLC is disregarded, so its sales are on the owner's return
          (money.tax). Public's API gives tax lots, not the 1099 (its
          documentsApi capability is false), so the forms come from
          Public's documents page.
        '';
        source = "https://www.irs.gov/forms-pubs/about-form-8949";
        checked = "2026-11-04";
        applies = {
          entities = [
            "mirazo"
            "jingzo"
          ];
          accounts = [
            "public-mirazo"
            "public-jingzo"
            "ibkr-jingzo"
          ];
          instruments = [
            "equity"
            "option"
          ];
        };
        constraint.obligation.form = "Form 8949, Schedule D";
      };

      irs-1256-contracts = {
        authority = "irs";
        citation = "26 U.S.C. §1256; Form 6781";
        title = "Section 1256 contracts: 60/40";
        summary = ''
          Regulated futures contracts, nonequity options (options on
          broad-based indexes such as SPX) and certain others are marked to
          market at year end and taxed 60% long-term, 40% short-term, on
          Form 6781 (money.obligations). SPY options are options on an ETF,
          equity options, so they are not §1256 contracts and fall under
          Form 8949. Whether Kalshi's event contracts, cleared swaps under
          the Commodity Exchange Act (Public's risk disclosure), are §1256
          contracts is not settled by anything read: the broker's tax
          documents decide the year's treatment, recorded here when they do.
        '';
        source = "https://www.law.cornell.edu/uscode/text/26/1256";
        more = [
          "https://www.irs.gov/forms-pubs/about-form-6781"
          "https://www.irs.gov/publications/p550"
        ];
        checked = "2026-11-04";
        applies = {
          entities = [
            "mirazo"
            "jingzo"
          ];
          accounts = [
            "public-mirazo"
            "public-jingzo"
            "ibkr-jingzo"
          ];
          instruments = [
            "option"
            "event-contract"
          ];
        };
        constraint.obligation.form = "Form 6781";
      };

      cftc-kalshi-dcm = {
        authority = "cftc";
        citation = "Commodity Exchange Act §5 (7 U.S.C. §7), designated contract markets; KalshiEX LLC";
        title = "Kalshi is a CFTC-designated contract market";
        summary = ''
          Event contracts are commodity derivatives under the Commodity
          Exchange Act, not securities: they trade on a designated contract
          market, are cleared by a derivatives clearing organization, and
          are reached through a futures commission merchant, all under the
          CFTC, not FINRA or the SEC. The CFTC's own DCM list was not read
          from this session (the host is off the allowlist); Kalshi's
          designation is stated by Public's event-contracts risk disclosure
          (read 2026-11-04: KalshiEx LLC, a DCM registered with the CFTC;
          KalshiKlear LLC, its DCO).
        '';
        source = "https://www.cftc.gov/IndustryOversight/TradingOrganizations/DCMs/index.htm";
        more = [ "https://public.com/disclosures/eventcontractsrisk" ];
        checked = null;
        applies = {
          entities = [
            "mirazo"
            "jingzo"
          ];
          accounts = [
            "public-mirazo"
            "public-jingzo"
          ];
          instruments = [ "event-contract" ];
        };
      };

      public-event-contracts = {
        authority = "public";
        citation = "Open to the Public Investing, Event Contracts Customer Agreement and Event Contracts Risk Disclosure (2026-08-20)";
        title = "Event contracts on Public";
        summary = ''
          Public Investing and Apex Clearing are CFTC-registered futures
          commission merchants and NFA members (Public: NFA ID 0465334);
          Public routes an event-contract order through Apex to KalshiEx,
          the DCM, and KalshiKlear clears it; the contracts are cleared
          swaps, and the event-contracts account is separate from the
          brokerage account under its own agreement. So every event
          contract the strategies trade is Kalshi's (the KALSHI symbol
          prefix), bought YES or NO outright (trading.limits). Whether the
          account has event contracts turned on is the Gap in
          modules/cloudflare/README.md; the preflight is the check.
        '';
        source = "https://public.com/disclosures/eventcontractscustomeragreement";
        more = [
          "https://public.com/disclosures/eventcontractsrisk"
          "https://public.com/prediction-markets"
        ];
        checked = "2026-11-04";
        applies = {
          entities = [
            "mirazo"
            "jingzo"
          ];
          accounts = [
            "public-mirazo"
            "public-jingzo"
          ];
          instruments = [ "event-contract" ];
        };
        constraint.exchange.symbol = "KALSHI";
      };
    };

    perSystem =
      { pkgs, ... }:
      {
        checks.compliance-rules =
          assert lib.assertMsg (problems == [ ]) (
            "modules/compliance:\n" + lib.concatMapStrings (p: "  - ${p}\n") problems
          );
          pkgs.runCommand "compliance-rules"
            {
              nativeBuildInputs = [ pkgs.lean4 ];
              facts = rendered;
              passAsFile = [ "facts" ];
            }
            ''
              cat ${./_lean/Rules.lean} "$factsPath" > Check.lean
              lean Check.lean
              touch $out
            '';

        packages.compliance-index = pkgs.writeShellApplication {
          name = "compliance-index";
          text = builtins.seq (lib.assertMsg (problems == [ ]) (lib.concatStringsSep "\n" problems)) ''
            case "''${1:-}" in
              --json) cat ${pkgs.writeText "compliance-rules.json" indexJson} ;;
              "") cat ${pkgs.writeText "compliance-rules.md" indexMd} ;;
              *) echo "usage: compliance-index [--json]" >&2; exit 2 ;;
            esac
          '';
        };
      };
  };
}
