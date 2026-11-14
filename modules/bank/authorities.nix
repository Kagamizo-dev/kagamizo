# What governs the bank, and what binds it (./bank.nix): every authority
# the owner and the entities answer to, with every interface a machine can
# use to read, file or pay; and every provider's terms, clause by clause,
# with what each permits, forbids or requires. Researched 2026-11-07 from
# the authorities' and providers' own pages (each url below).
#
#   bank.authorities.<a>   who it is, and its interfaces: access, second
#                          factor, what a machine can do there
#   bank.terms.<provider>  the clauses that bind our automation
#
# The rules (checks.bank-authorities, ./_lean/Authorities.lean): no
# interface the bank relies on needs a phone number (SMS) as its second
# factor; every clause cites its page; and because Public's API terms cover
# only accounts opened in the developer's own name (Individual Trader API
# Agreement, s1.a), every revenue source at Public lands on a person's
# account, never an entity's.
{ lib, config, ... }:
let
  inherit (lib) mkOption types;
  top = config;
  cfg = config.bank;
  q = builtins.toJSON;

  interface = types.submodule {
    options = {
      name = mkOption { type = types.str; };
      access = mkOption {
        type = types.enum [
          "open"
          "account"
          "transmitter-only"
          "paid"
        ];
      };
      secondFactor = mkOption {
        type = types.enum [
          "none"
          "authenticator"
          "mailed-pin"
          "sms"
          "unknown"
        ];
      };
      can = mkOption {
        type = types.listOf (
          types.enum [
            "read"
            "file"
            "pay"
          ]
        );
      };
      api = mkOption {
        type = types.bool;
        description = "Whether a machine can use it without a browser.";
      };
      relied = mkOption {
        type = types.bool;
        default = false;
        description = "Whether the bank relies on it today.";
      };
      url = mkOption { type = types.strMatching "https://.*"; };
    };
  };

  authority = types.submodule {
    options = {
      name = mkOption { type = types.str; };
      kind = mkOption {
        type = types.enum [
          "federal-tax"
          "treasury"
          "financial-crimes"
          "securities"
          "derivatives"
          "self-regulatory"
          "state"
          "rules-text"
        ];
      };
      interfaces = mkOption {
        type = types.listOf interface;
        default = [ ];
      };
    };
  };

  clause = types.submodule {
    options = {
      section = mkOption { type = types.str; };
      says = mkOption {
        type = types.str;
        description = "The clause, quoted or closely paraphrased.";
      };
      effect = mkOption {
        type = types.enum [
          "permits"
          "forbids"
          "requires"
        ];
      };
      bears = mkOption {
        type = types.str;
        description = "What in the repository it constrains.";
      };
      url = mkOption { type = types.strMatching "https://.*"; };
    };
  };
in
{
  options.bank = {
    authorities = mkOption {
      type = types.attrsOf authority;
      default = { };
    };
    terms = mkOption {
      type = types.attrsOf (types.listOf clause);
      default = { };
    };
  };

  config = {
    bank.authorities = {
      irs = {
        name = "Internal Revenue Service";
        kind = "federal-tax";
        interfaces = [
          {
            name = "forms, instructions and the Internal Revenue Bulletin";
            access = "open";
            secondFactor = "none";
            can = [ "read" ];
            api = true;
            relied = true;
            url = "https://www.irs.gov/forms-instructions";
          }
          {
            name = "Online Account (transcripts, balance, payments)";
            access = "account";
            secondFactor = "authenticator";
            can = [
              "read"
              "pay"
            ];
            api = false;
            url = "https://www.irs.gov/help/creating-an-account-for-irsgov";
          }
          {
            name = "Direct Pay";
            access = "open";
            secondFactor = "none";
            can = [ "pay" ];
            api = false;
            url = "https://www.irs.gov/payments/direct-pay";
          }
          {
            name = "IRIS (information returns: 1099-NEC and MISC, web and A2A)";
            access = "account";
            secondFactor = "authenticator";
            can = [ "file" ];
            api = true;
            url = "https://www.irs.gov/pub/irs-pdf/p5718.pdf";
          }
          {
            name = "MeF (e-filing the 1040)";
            access = "transmitter-only";
            secondFactor = "unknown";
            can = [ "file" ];
            api = true;
            url = "https://www.irs.gov/e-file-providers/modernized-e-file-mef-internet-filing";
          }
        ];
      };
      treasury = {
        name = "US Treasury (EFTPS, FiscalData)";
        kind = "treasury";
        interfaces = [
          {
            name = "FiscalData API (interest rates, Treasury statements)";
            access = "open";
            secondFactor = "none";
            can = [ "read" ];
            api = true;
            url = "https://fiscaldata.treasury.gov/api-documentation/";
          }
          {
            name = "EFTPS (federal tax payments)";
            access = "account";
            secondFactor = "mailed-pin";
            can = [ "pay" ];
            api = false;
            url = "https://www.eftps.gov/eftps/";
          }
        ];
      };
      fincen = {
        name = "Financial Crimes Enforcement Network";
        kind = "financial-crimes";
        interfaces = [
          {
            name = "BOI and FBAR guidance (BOI: US companies exempt from 2026-08-14; FBAR: foreign accounts over $10,000)";
            access = "open";
            secondFactor = "none";
            can = [ "read" ];
            api = false;
            url = "https://www.fincen.gov/boi";
          }
        ];
      };
      sec = {
        name = "Securities and Exchange Commission";
        kind = "securities";
        interfaces = [
          {
            name = "EDGAR APIs (data.sec.gov: filings, XBRL; a User-Agent, 10 requests a second)";
            access = "open";
            secondFactor = "none";
            can = [ "read" ];
            api = true;
            url = "https://www.sec.gov/search-filings/edgar-search-assistance/accessing-edgar-data";
          }
        ];
      };
      finra = {
        name = "FINRA";
        kind = "self-regulatory";
        interfaces = [
          {
            name = "BrokerCheck";
            access = "open";
            secondFactor = "none";
            can = [ "read" ];
            api = false;
            url = "https://brokercheck.finra.org";
          }
          {
            name = "API Developer Center (datasets; paid credentials)";
            access = "paid";
            secondFactor = "unknown";
            can = [ "read" ];
            api = true;
            url = "https://developer.finra.org/fees/public";
          }
        ];
      };
      cftc = {
        name = "Commodity Futures Trading Commission and the NFA";
        kind = "derivatives";
        interfaces = [
          {
            name = "Public Reporting Environment (Commitments of Traders, swaps; Socrata API)";
            access = "open";
            secondFactor = "none";
            can = [ "read" ];
            api = true;
            url = "https://publicreporting.cftc.gov";
          }
          {
            name = "NFA BASIC (registrations: Public's NFA ID 0465334)";
            access = "open";
            secondFactor = "none";
            can = [ "read" ];
            api = false;
            url = "https://www.nfa.futures.org/BasicNet/";
          }
        ];
      };
      wyoming-sos = {
        name = "Wyoming Secretary of State";
        kind = "state";
        interfaces = [
          {
            name = "Business search (entity status)";
            access = "open";
            secondFactor = "none";
            can = [ "read" ];
            api = false;
            url = "https://wyobiz.wyo.gov/Business/FilingSearch.aspx";
          }
          {
            name = "Annual report filing and license tax (web form, card payment)";
            access = "open";
            secondFactor = "none";
            can = [
              "file"
              "pay"
            ];
            api = false;
            url = "https://wyobiz.wyo.gov/Business/AnnualReport.aspx";
          }
        ];
      };
      rules-text = {
        name = "eCFR and the Federal Register";
        kind = "rules-text";
        interfaces = [
          {
            name = "eCFR API (the rules' current text)";
            access = "open";
            secondFactor = "none";
            can = [ "read" ];
            api = true;
            url = "https://www.ecfr.gov/developers/documentation/api/v1";
          }
          {
            name = "Federal Register API (rule changes)";
            access = "open";
            secondFactor = "none";
            can = [ "read" ];
            api = true;
            url = "https://www.federalregister.gov/developers/documentation/api/v1";
          }
        ];
      };
    };

    bank.terms = {
      public = [
        {
          section = "Individual Trader API Agreement s1.a";
          says = "covers accounts that Developer has opened in their own name";
          effect = "requires";
          bears = "trading revenue at Public lands on a person's account (checks.bank-authorities)";
          url = "https://public.com/documents/individual-api-program";
        }
        {
          section = "s1.c";
          says = "solely for Developer's own personal use";
          effect = "permits";
          bears = "automated trading on the owner's own account, by their own applications";
          url = "https://public.com/documents/individual-api-program";
        }
        {
          section = "s4.a.xx, s4.a.xxii";
          says = "no automated scripts other than your Applications; no automatic mirroring of trades across different users";
          effect = "forbids";
          bears = "trade runs as the owner's own application; no copy-trading";
          url = "https://public.com/documents/individual-api-program";
        }
        {
          section = "s4.i";
          says = "keep records for 12 months";
          effect = "requires";
          bears = "the paper and live ledgers are kept at least 12 months";
          url = "https://public.com/documents/individual-api-program";
        }
        {
          section = "FAQ";
          says = "10 requests per second per account, across all endpoints";
          effect = "requires";
          bears = "the Public client's rate limit";
          url = "https://public.com/api/docs/faq";
        }
      ];
      mercury = [
        {
          section = "Terms s1.4";
          says = "no robot, spider, scraper or other automated means without written permission";
          effect = "forbids";
          bears = "Mercury is reached only through its API and MCP, never by browser automation";
          url = "https://mercury.com/legal/terms";
        }
        {
          section = "Terms s3.2";
          says = "a third-party AI agent may connect through an API, plugin, connector or similar integration Mercury makes available";
          effect = "permits";
          bears = "the agents' reads through mercury-cli";
          url = "https://mercury.com/legal/terms";
        }
        {
          section = "API token security policies";
          says = "Read and Write tokens need an IP allow-list; tokens unused for 45 days are deleted, and unused write is downgraded";
          effect = "requires";
          bears = "write tokens only from jingzo-host's address; a keep-alive within 45 days";
          url = "https://docs.mercury.com/docs/api-token-security-policies";
        }
      ];
      northwest = [
        {
          section = "Acceptable Use";
          says = "you may not scrape, reverse-engineer, or misuse our systems";
          effect = "forbids";
          bears = "Northwest is reached only through its official MCP server";
          url = "https://www.northwestregisteredagent.com/terms-policy/acceptable-use";
        }
        {
          section = "AI Terms";
          says = "assistants perform only limited actions";
          effect = "requires";
          bears = "the northwest wrapper's actions stay within the MCP's tools";
          url = "https://www.northwestregisteredagent.com/terms-policy/ai-terms";
        }
      ];
    };

    perSystem =
      { config, ... }:
      let
        provider = a: top.accounts.held.${a}.provider or "";
        kind = e: top.identity.entities.${e}.kind or "";
      in
      {
        checks.bank-authorities = config.kagamizo.leanCheck {
          name = "bank-authorities";
          source = ./_lean/Authorities.lean;
          facts = ''

            namespace Kagamizo.Authorities
            def interfaces : List Interface := [${
              lib.concatStringsSep ",\n  " (
                lib.concatLists (
                  lib.mapAttrsToList (
                    a: x:
                    map (
                      i:
                      "{ authority := ${q a}, name := ${q i.name}, sms := ${
                        lib.boolToString (i.secondFactor == "sms")
                      }, relied := ${lib.boolToString i.relied} }"
                    ) x.interfaces
                  ) cfg.authorities
                )
              )
            }]
            def clauses : List (String × String) := [${
              lib.concatStringsSep ", " (
                lib.concatLists (lib.mapAttrsToList (p: cs: map (c: "(${q p}, ${q c.url})") cs) cfg.terms)
              )
            }]
            def revenue : List Revenue := [${
              lib.concatStringsSep ", " (
                lib.mapAttrsToList (
                  n: r:
                  "{ name := ${q n}, provider := ${q (provider r.account)}, entityKind := ${q (kind r.entity)} }"
                ) cfg.revenue
              )
            }]

            theorem authorities_sound : sound interfaces clauses revenue = true := by decide +kernel
            end Kagamizo.Authorities
          '';
        };
      };
  };
}
