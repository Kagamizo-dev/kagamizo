# The services that could read Chase, Capital One and Credit One for the
# bank (none of the three has a consumer API), and what each is known to
# cover: the owner's rule of 2026-11-08 is to confirm a service covers
# everything before choosing it.
#
#   bank.aggregators.<p>       a provider: own-account use, cost, and per
#                              institution whether it is supported and its
#                              card transactions read, each with its source
#                              and the date it was verified (null: not yet,
#                              from search snippets only)
#   bank.aggregatorRequired    the institutions the bank must read
#   bank.aggregatorChoice      null until chosen: the provider, and the
#                              gaps the owner accepts by name
#
# checks.bank-aggregators: Lean (./_lean/Aggregators.lean) refuses a choice
# that is not acceptable: own accounts allowed, and every required
# institution covered with card transactions by a verified fact, or an
# accepted gap. Today every fact is unverified (this session's network
# reaches none of the providers), so no choice can pass yet.
{ lib, config, ... }:
let
  inherit (lib) mkOption types;
  cfg = config.bank;
  q = builtins.toJSON;
  fact = types.enum [
    "yes"
    "no"
    "unknown"
  ];
  coverage = types.submodule {
    options = {
      supported = mkOption { type = fact; };
      cardTransactions = mkOption {
        type = fact;
        description = "Whether its card accounts' transactions are read; yes too for an institution with no cards.";
      };
      source = mkOption { type = types.str; };
      verified = mkOption {
        type = types.nullOr (types.strMatching "[0-9]{4}-[0-9]{2}-[0-9]{2}");
        default = null;
        description = "The date it was read from the provider's own institution search; null while it rests on snippets.";
      };
    };
  };
  provider = types.submodule {
    options = {
      name = mkOption { type = types.str; };
      ownAccounts = mkOption {
        type = fact;
        description = "Whether its terms allow linking one's own accounts.";
      };
      cost = mkOption { type = types.str; };
      signup = mkOption {
        type = types.str;
        description = "What confirming its coverage takes.";
      };
      coverage = mkOption { type = types.attrsOf coverage; };
    };
  };
  institutions = [
    "chase-checking"
    "chase-cards"
    "capital-one-cards"
    "credit-one"
    "discover"
    "paypal"
  ];
  unknown = source: {
    supported = "unknown";
    cardTransactions = "unknown";
    inherit source;
  };
  snippet = "search snippets only, 2026-11-08: the provider's pages were blocked from the session";
  render =
    n: p:
    "{ name := ${q n}, ownAccounts := .${p.ownAccounts}, coverage := [${
      lib.concatStringsSep ", " (
        lib.mapAttrsToList (
          i: c:
          "{ institution := ${q i}, supported := .${c.supported}, cardTransactions := .${c.cardTransactions}, verified := ${
            lib.boolToString (c.verified != null)
          } }"
        ) p.coverage
      )
    }] }";
in
{
  options.bank = {
    aggregators = mkOption {
      type = types.attrsOf provider;
      default = { };
    };
    aggregatorRequired = mkOption {
      type = types.listOf (types.enum institutions);
      default = [ ];
    };
    aggregatorChoice = mkOption {
      type = types.nullOr (
        types.submodule {
          options = {
            provider = mkOption { type = types.enum (lib.attrNames cfg.aggregators); };
            acceptedGaps = mkOption {
              type = types.listOf (types.enum institutions);
              default = [ ];
              description = "Institutions the owner accepts the provider does not cover; read by their mailed statements instead.";
            };
          };
        }
      );
      default = null;
    };
  };

  config = {
    bank.aggregatorRequired = [
      "chase-checking"
      "chase-cards"
      "capital-one-cards"
      "credit-one"
    ];

    bank.aggregators = {
      stripe-fc = {
        name = "Stripe Financial Connections";
        ownAccounts = "unknown";
        cost = "per linked account (2022: $1.50 a verification); current price unread";
        signup = "Stripe's supported-institutions page, a sandbox test, and Stripe support's written answer on linking the owner's own accounts";
        coverage = lib.genAttrs institutions (_: unknown snippet) // {
          chase-cards = unknown "Stripe lists Chase among featured institutions; credit_card accounts exist, their transactions unconfirmed (${snippet})";
          capital-one-cards = unknown "Stripe lists Capital One among featured institutions (${snippet})";
        };
      };
      plaid = {
        name = "Plaid";
        ownAccounts = "unknown";
        cost = "a free Trial plan on production data for new US teams (10 Items, per Plaid's help centre snippet)";
        signup = "a free developer account: the Dashboard's institution search shows each bank's products, Transactions included";
        coverage = lib.genAttrs institutions (_: unknown snippet) // {
          chase-cards = unknown "widely reported; Plaid says Transactions covers credit cards (${snippet})";
          capital-one-cards = unknown "access restored after the 2021 dispute; history reportedly about 90 days (${snippet})";
          credit-one = unknown "a third-party tracker (openbankingtracker.com) lists it (${snippet})";
        };
      };
      simplefin = {
        name = "SimpleFIN Bridge";
        ownAccounts = "yes";
        cost = "$1.50 a month or $15 a year, 25 institutions";
        signup = "an account at bridge.simplefin.org: search its institutions, link one card and see its transactions";
        coverage = lib.genAttrs institutions (_: unknown snippet);
      };
      teller = {
        name = "Teller";
        ownAccounts = "unknown";
        cost = "free development tier, 100 enrollments";
        signup = "a free developer account; its institutions endpoint lists the banks";
        coverage = lib.genAttrs institutions (_: unknown snippet) // {
          chase-checking = unknown "Teller's own example response uses Chase (${snippet})";
        };
      };
    };

    perSystem =
      { config, ... }:
      {
        checks.bank-aggregators = config.kagamizo.leanCheck {
          name = "bank-aggregators";
          source = ./_lean/Aggregators.lean;
          facts = ''

            namespace Kagamizo.Aggregators
            def providers : List Provider := [${lib.concatStringsSep ",\n  " (lib.mapAttrsToList render cfg.aggregators)}]
            def required : List String := ${q cfg.aggregatorRequired}
            ${
              if cfg.aggregatorChoice == null then
                ''
                  /-- No provider is chosen yet. -/
                  example : True := trivial''
              else
                ''
                  def chosen : Provider := ${
                    render cfg.aggregatorChoice.provider cfg.aggregators.${cfg.aggregatorChoice.provider}
                  }
                  /-- The chosen provider covers everything required, or the owner accepted the gap. -/
                  theorem choice_acceptable : acceptable chosen required ${q cfg.aggregatorChoice.acceptedGaps} = true := by decide''
            }
            end Kagamizo.Aggregators
          '';
        };
      };
  };
}
