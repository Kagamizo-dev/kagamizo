# The bank: the owner's own bank, as one app (the owner's direction,
# 2026-11-07). Legal and tax identity is bound to every source of revenue:
# the treasury (Mercury), the brokerages (Public, IBKR), trading paper and
# live, the books and the tax (../money), the legal record (../legal), the
# registered agent (../northwest), the rules (../compliance) and the credit
# lines, each a service of the bank, with the legal and accounting teams as
# the bank's lawyers and accountants. Every flow in or out, loans between
# entities included, goes through it (../money flows).
#
#   bank.services.<s>  a service: the module that runs it, its role, the
#                      accounts it holds and the teams that run it
#   bank.revenue.<r>   a source of revenue: the entity it belongs to, the
#                      account it lands in, and where it lands on a return
#
#   packages.bank-book  the bank as JSON: services, revenue, accounts by
#                       entity, flows, and the year's obligations
#   checks.bank         Lean (./_lean/Bank.lean): every money account is
#                       held by a service; every revenue source lands in its
#                       own entity's account, an entity that is taxed and
#                       has its obligations declared; every service's teams
#                       exist
{ lib, config, ... }:
let
  inherit (lib) mkOption types;
  top = config;
  cfg = config.bank;
  q = builtins.toJSON;
  held = config.accounts.held;
  modules = lib.attrNames (
    lib.filterAttrs (n: t: t == "directory" && !lib.hasPrefix "_" n) (builtins.readDir ../.)
  );
  # The providers whose accounts hold or move money, or record credit.
  financial = [
    "mercury"
    "public"
    "ibkr"
    "chase"
    "capital-one"
    "credit-one"
    "discover"
    "paypal"
    "experian"
    "northwest"
  ];
  moneyAccounts = lib.attrNames (lib.filterAttrs (_: a: lib.elem a.provider financial) held);
  year = 2026;
  obligations = config.money.obligations year;
  teams = lib.attrNames config.agents.charters;

  service = types.submodule {
    options = {
      module = mkOption { type = types.enum modules; };
      role = mkOption {
        type = types.enum [
          "treasury"
          "brokerage"
          "trading"
          "accounting"
          "tax"
          "credit"
          "legal"
          "registered-agent"
          "compliance"
        ];
      };
      accounts = mkOption {
        type = types.listOf (types.enum (lib.attrNames held));
        default = [ ];
      };
      teams = mkOption { type = types.nonEmptyListOf (types.enum teams); };
      why = mkOption { type = types.str; };
    };
  };

  source = types.submodule {
    options = {
      entity = mkOption { type = types.enum (lib.attrNames config.identity.entities); };
      account = mkOption { type = types.enum (lib.attrNames held); };
      kind = mkOption {
        type = types.enum [
          "trading"
          "research"
          "interest"
        ];
      };
      lands = mkOption {
        type = types.str;
        description = "Where it lands on a return, or what the accountants have still to settle.";
      };
      settled = mkOption {
        type = types.bool;
        description = "Whether its tax treatment is settled; an open one is the accountants' work.";
      };
    };
  };

  ownerOf = a: held.${a}.owner or "";
  # A due date, or "date open" (sorting last) where it waits on a fact.
  dueOf = o: if (o.due or null) == null then "date open" else o.due;
  # An obligation's name in bank.status, and its state.
  oid = o: "${toString year}/${o.entity or ""}/${o.form or ""}";
  stateOf =
    o:
    if cfg.status ? ${oid o} then
      "${cfg.status.${oid o}.state} ${cfg.status.${oid o}.date}"
    else if (o.due or null) != null && o.due < cfg.asOf then
      "past due, no status"
    else
      "open";
  pastDue = lib.filter (o: stateOf o == "past due, no status") obligations;
  byEntity = lib.groupBy ownerOf moneyAccounts;
in
{
  options.bank = {
    asOf = mkOption {
      type = types.strMatching "[0-9]{4}-[0-9]{2}-[0-9]{2}";
      description = "The day the bank's statuses are current as of, moved forward each session: an open obligation due before it is past due.";
    };
    status = mkOption {
      type = types.attrsOf (
        types.submodule {
          options = {
            state = mkOption {
              type = types.enum [
                "filed"
                "paid"
                "not-owed"
                "extended"
              ];
            };
            date = mkOption { type = types.strMatching "[0-9]{4}-[0-9]{2}-[0-9]{2}"; };
            evidence = mkOption {
              type = types.str;
              description = "What shows it: a confirmation number's Pass item, a statement, the owner's dated word.";
            };
          };
        }
      );
      default = { };
      description = "Each obligation's status, keyed year/entity/form as the bank names it; an obligation without one is open.";
    };
    services = mkOption {
      type = types.attrsOf service;
      default = { };
    };
    revenue = mkOption {
      type = types.attrsOf source;
      default = { };
    };
    book = mkOption {
      type = types.attrsOf types.anything;
      readOnly = true;
      description = "The bank as data, for its page and packages.bank-book.";
      default = {
        inherit (cfg) services revenue;
        inherit year obligations;
        inherit (cfg) asOf status;
        pastDue = map oid pastDue;
        accounts = byEntity;
        flows = config.money.flows;
      };
    };
  };

  config = {
    bank = {
      asOf = "2026-11-07";
      services =
        let
          accountants = [
            "accounting-jingzo"
            "accounting-mirazo"
          ];
          lawyers = [
            "legal-jingzo"
            "legal-mirazo"
          ];
        in
        {
          treasury = {
            module = "mercury";
            role = "treasury";
            accounts = [
              "mercury"
              "mercury-jingzo"
              "mercury-mirazo"
            ];
            teams = accountants;
            why = "the bank accounts and their cards: every payment ends on a Mercury card, every flow starts or ends here";
          };
          brokerage = {
            module = "public";
            role = "brokerage";
            accounts = [
              "public-mirazo"
              "public-jingzo"
            ];
            teams = accountants;
            why = "the brokerage accounts, read nightly into the books, traded only by the owner's approval";
          };
          brokerage-ibkr = {
            module = "ibkr";
            role = "brokerage";
            accounts = [ "ibkr-jingzo" ];
            teams = accountants;
            why = "the second brokerage, for when Public cannot";
          };
          trading = {
            module = "trading";
            role = "trading";
            accounts = [ "public-mirazo" ];
            teams = [ "research-jingzo" ] ++ accountants;
            why = "the strategies: paper days now, live only after the gate and the owner's dated promotion";
          };
          books = {
            module = "money";
            role = "accounting";
            accounts = [
              "chase-mirazo"
              "paypal-mirazo"
            ];
            teams = accountants;
            why = "the books: every transaction's treatment, the flows and floors, the nightly brokerage ledger";
          };
          tax = {
            module = "money";
            role = "tax";
            teams = accountants;
            why = "who files what, and every form and payment due each tax year, with its date and source";
          };
          credit = {
            module = "money";
            role = "credit";
            accounts = [
              "capital-one-mirazo"
              "credit-one-mirazo"
              "discover-mirazo"
              "experian"
            ];
            teams = accountants;
            why = "the lines of credit and the credit file: limits, fees, what pays each, alerts and freezes";
          };
          legal = {
            module = "legal";
            role = "legal";
            teams = lawyers;
            why = "the entities' legal records and the documents rendered from them";
          };
          registered-agent = {
            module = "northwest";
            role = "registered-agent";
            accounts = [
              "northwest-jingzo"
              "northwest-kagamizo"
            ];
            teams = lawyers;
            why = "the registered agent: formations, mail, annual reports";
          };
          compliance = {
            module = "compliance";
            role = "compliance";
            teams = lawyers ++ [
              "governance-jingzo"
              "governance-mirazo"
            ];
            why = "FINRA, SEC, IRS and CFTC rules, checked against every strategy";
          };
        };

      revenue = {
        trading-weather-rules = {
          entity = "mirazo";
          account = "public-mirazo";
          kind = "trading";
          lands = "the owner's 1040; event contracts' treatment (capital gains on Form 8949 and Schedule D, or otherwise) is still for the accountants to settle";
          settled = false;
        };
        research = {
          entity = "jingzo";
          account = "mercury-jingzo";
          kind = "research";
          lands = "published research's income, on Jingzo's return as money.tax declares it";
          settled = false;
        };
      };
    };

    # The bank's card: its page shows what waits on the owner, the year's
    # obligations, the revenue, the accounts by entity and the flows.
    shell.apps.bank = {
      name = "Bank";
      category = "money";
      kind = "module";
      module = "bank";
      description = "Our own bank: treasury, brokerage, trading, books, tax, legal and the registered agent";
      view = [
        {
          title = "Waiting on you";
          rows =
            map (o: {
              title = "Past due without a status: ${o.form} (${o.entity})";
              detail = "due ${o.due}: say whether it was filed, paid or not owed, with evidence";
            }) pastDue
            ++
              map
                (i: {
                  inherit (i) title;
                  detail = if i.decision != null then top.plan.decisions.${i.decision}.question else "your action";
                })
                (
                  lib.filter (
                    i:
                    (i.track == "bank" || i.track == "trading")
                    && i.status != "done"
                    && lib.elem i.blocked [
                      "owner-decision"
                      "owner-action"
                    ]
                  ) (lib.attrValues top.plan.items)
                );
        }
        {
          title = "Obligations, ${toString year}";
          rows = map (o: {
            title = "${dueOf o} · ${o.form or "?"} (${o.entity or "?"}): ${stateOf o}";
            detail = o.what or "";
          }) (lib.sort (a: b: dueOf a < dueOf b) obligations);
        }
        {
          title = "Revenue";
          rows = lib.mapAttrsToList (n: r: {
            title = "${n}: into ${r.account} (${r.entity})";
            detail = "${r.kind}; ${r.lands}";
          }) cfg.revenue;
        }
        {
          title = "Accounts, by entity";
          rows = lib.mapAttrsToList (e: accs: {
            title = e;
            detail = lib.concatStringsSep ", " accs;
          }) byEntity;
        }
        {
          title = "Services";
          rows = lib.mapAttrsToList (n: s: {
            title = "${n} (${s.role})";
            detail = "modules/${s.module}: ${s.why}";
          }) cfg.services;
        }
      ];
    };

    perSystem =
      { pkgs, config, ... }:
      {
        packages.bank-book = pkgs.writeText "bank-book.json" (builtins.toJSON cfg.book);
        checks.bank = config.kagamizo.leanCheck {
          name = "bank";
          source = ./_lean/Bank.lean;
          facts = ''

            namespace Kagamizo.Bank
            def moneyAccounts : List String := ${q moneyAccounts}
            def owners : List (String × String) := [${
              lib.concatMapStringsSep ", " (a: "(${q a}, ${q (ownerOf a)})") (lib.attrNames held)
            }]
            def services : List Service := [${
              lib.concatStringsSep ",\n  " (
                lib.mapAttrsToList (
                  n: s: "{ name := ${q n}, accounts := ${q s.accounts}, teams := ${q s.teams} }"
                ) cfg.services
              )
            }]
            def revenue : List Source := [${
              lib.concatStringsSep ",\n  " (
                lib.mapAttrsToList (
                  n: r: "{ name := ${q n}, entity := ${q r.entity}, account := ${q r.account} }"
                ) cfg.revenue
              )
            }]
            def taxed : List String := ${q (lib.attrNames top.money.tax)}
            def owing : List String := ${q (lib.unique (map (o: o.entity or "") obligations))}
            def teams : List String := ${q teams}
            def obligations : List String := ${q (map oid obligations)}
            def statuses : List (String × String) := [${
              lib.concatStringsSep ", " (lib.mapAttrsToList (k: s: "(${q k}, ${q s.evidence})") cfg.status)
            }]

            theorem bank_sound : sound moneyAccounts owners services revenue taxed owing teams obligations statuses = true := by decide +kernel
            end Kagamizo.Bank
          '';
        };
      };
  };
}
