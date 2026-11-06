# Money moving between held accounts, declared before it moves: who it goes
# from and to, how much (a sum, or a rule for the excess over a threshold),
# what it is between the owners (personal, a contribution, a draw, a
# transfer, a sweep), when, and the owner's dated approval. Public moves no
# money by API (modules/public), so every flow here is the owner's hand;
# the declaration is what the books expect to see.
#
#   money.flows.<name> = { from; to; usd | rule; as; when; approvedBy; }
#   money.floors.<account> = { usd; setBy; why; }    the cash an account keeps
#   money.borrowing.<account> = { enabled; kind; maxUsd; approvedBy; }
#
# The owner's decisions of 2026-11-05: trading is on the owner's own Public
# account, funded from and returned to Mercury personal; capital stays
# invested, so Mercury keeps only an operating floor, the excess above it
# goes to Public, and Public refills Mercury only when it falls below the
# floor. Public's API moves no money, so the nightly ledger proposes each
# flow's amount and the owner makes it by hand. Borrowing against holdings
# is declared and switched off.
#
# ./_lean/Flows.lean proves the rules, rendered from these declarations
# (checks.money-flows): a flow between two owners' accounts is booked as a
# contribution or a draw, a personal flow stays with one owner, and no flow
# is executable until approvedBy is a date.
{ lib, config, ... }:
let
  inherit (lib) mkOption types;
  cfg = config.money.flows;
  held = config.accounts.held;
  date = types.strMatching "[0-9]{4}-[0-9]{2}-[0-9]{2}";

  flow = types.submodule {
    options = {
      from = mkOption {
        type = types.enum (lib.attrNames held);
        description = "The held account the money leaves.";
      };
      to = mkOption {
        type = types.enum (lib.attrNames held);
        description = "The held account it arrives on.";
      };
      usd = mkOption {
        type = types.nullOr types.ints.positive;
        default = null;
        description = "A fixed sum; null when `rule` says how much.";
      };
      rule = mkOption {
        type = types.nullOr (
          types.submodule {
            options = {
              aboveUsd = mkOption {
                type = types.nullOr types.ints.positive;
                default = null;
                description = "Excess: the flow runs once the source holds more than this.";
              };
              keepUsd = mkOption {
                type = types.nullOr types.ints.unsigned;
                default = null;
                description = "Excess: what stays behind; the excess over it moves.";
              };
              refillToUsd = mkOption {
                type = types.nullOr types.ints.positive;
                default = null;
                description = "Refill: when the destination holds less than this, enough moves to bring it back.";
              };
            };
          }
        );
        default = null;
        description = "The excess over a threshold, instead of a fixed sum.";
      };
      as = mkOption {
        type = types.enum [
          "personal"
          "contribution"
          "draw"
          "transfer"
          "sweep"
        ];
        description = ''
          personal: the owner's own money between their own accounts;
          contribution: into a company from its owner; draw: out of a company
          to its owner; transfer: between a company's own accounts; sweep: a
          rule-driven return of excess to where it came from.
        '';
      };
      when = mkOption {
        type = types.str;
        description = "The condition it runs under, in words.";
      };
      approvedBy = mkOption {
        type = types.nullOr date;
        default = null;
        description = "The date of the owner's approval; null is not approved, never executable.";
      };
    };
  };

  owner = a: held.${a}.owner;
  q = builtins.toJSON;
  facts = ''
    namespace Kagamizo.Money

    def flows : List Flow := [
    ${lib.concatStringsSep ",\n" (
      lib.mapAttrsToList (
        n: f:
        "  { name := ${q n}, fromOwner := ${q (owner f.from)}, toOwner := ${q (owner f.to)}, kind := .${f.as}, approved := ${
            lib.boolToString (f.approvedBy != null)
          } }"
      ) cfg
    )}
    ]

    /-- Every declared flow is booked right between its owners. -/
    theorem flows_booked : flows.all Flow.booked = true := by decide

    def borrowing : List Borrowing := [
    ${lib.concatStringsSep ",\n" (
      lib.mapAttrsToList (
        n: b:
        "  { account := ${q n}, enabled := ${lib.boolToString b.enabled}, approved := ${
            lib.boolToString (b.approvedBy != null)
          }, maxUsd := ${toString b.maxUsd} }"
      ) config.money.borrowing
    )}
    ]

    /-- Borrowing is on only with the owner's dated approval and a cap. -/
    theorem borrowing_gated : borrowing.all Borrowing.gated = true := by decide

    /-- No declared flow is executable yet: none is approved. -/
    theorem nothing_executable_yet : flows.all (fun f => !f.executable) = true := by decide

    end Kagamizo.Money
  '';

  problems = lib.concatLists (
    lib.mapAttrsToList (
      n: f:
      lib.optional ((f.usd == null) == (f.rule == null)) "money.flows.${n}: exactly one of usd and rule"
      ++ lib.optional (f.from == f.to) "money.flows.${n}: from and to are the same account"
      ++ lib.optional (
        f.rule != null && (f.rule.aboveUsd == null) != (f.rule.keepUsd == null)
      ) "money.flows.${n}: an excess rule names both aboveUsd and keepUsd"
      ++ lib.optional (
        f.rule != null && (f.rule.aboveUsd != null) == (f.rule.refillToUsd != null)
      ) "money.flows.${n}: a rule is either an excess (aboveUsd, keepUsd) or a refill (refillToUsd)"
      ++ lib.optional (
        f.rule != null && f.rule.aboveUsd != null && f.rule.keepUsd > f.rule.aboveUsd
      ) "money.flows.${n}: keeps more than its threshold, so nothing would ever move"
      ++
        lib.optional
          (
            (owner f.from != owner f.to) != lib.elem f.as [
              "contribution"
              "draw"
            ]
          )
          "money.flows.${n}: between ${owner f.from} and ${owner f.to}, so `as` is contribution or draw exactly when they differ"
      ++ lib.optional (
        f.as == "contribution" && held.${f.to}.owner == held.${f.from}.owner
      ) "money.flows.${n}: a contribution goes to another entity"
    ) cfg
  );
in
{
  options.money = {
    flows = mkOption {
      type = types.attrsOf flow;
      default = { };
    };
    flowsChecked = mkOption {
      type = types.raw;
      readOnly = true;
    };
    floors = mkOption {
      type = types.attrsOf (
        types.submodule {
          options = {
            usd = mkOption {
              type = types.ints.positive;
              description = "The cash the account keeps; flows move what is above it or refill to it.";
            };
            setBy = mkOption {
              type = types.enum [
                "owner"
                "placeholder"
              ];
              description = "Whether the owner set it, or it holds a place until they do.";
            };
            why = mkOption { type = types.str; };
          };
        }
      );
      default = { };
    };
    borrowing = mkOption {
      type = types.attrsOf (
        types.submodule {
          options = {
            enabled = mkOption {
              type = types.bool;
              default = false;
              description = "Whether the account may borrow against its holdings.";
            };
            kind = mkOption {
              type = types.enum [
                "margin"
                "pledged-line"
              ];
            };
            maxUsd = mkOption {
              type = types.ints.unsigned;
              default = 0;
              description = "The most it may owe.";
            };
            approvedBy = mkOption {
              type = types.nullOr date;
              default = null;
              description = "The owner's dated approval; enabled needs one.";
            };
          };
        }
      );
      default = { };
    };
  };

  config = {
    money = {
      flowsChecked =
        assert lib.assertMsg (problems == [ ]) (
          "modules/money/_flows.nix:\n" + lib.concatMapStrings (p: "  - ${p}\n") problems
        );
        cfg;

      # The owner's answer, 2026-11-05: the host reads the ledger nightly,
      # read-only (./_ledger.nix).
      ledger.enable = true;

      # Mercury personal keeps an operating floor; the owner sets its amount
      # (500 holds the place).
      floors.mercury-mirazo = {
        usd = 500;
        setBy = "placeholder";
        why = "the cash the owner keeps liquid; everything above it stays invested";
      };

      # Borrowing against the brokerage is declared and off: on a small account
      # a margin loan adds interest and forced-sale risk for no gain.
      borrowing.public-mirazo = {
        enabled = false;
        kind = "margin";
      };

      # The trading plan (HANDOFF.md, 2026-11-02, and the owner's decisions of
      # 2026-11-05): a $100 seed after five paper days, then the floor rules.
      # All wait on the owner's dated approval.
      flows =
        let
          floor = config.money.floors.mercury-mirazo.usd;
        in
        {
          public-seed = {
            from = "mercury-mirazo";
            to = "public-mirazo";
            usd = 100;
            as = "personal";
            when = "after five paper days (trading.strategies.<s>.stage = paper, five dated days)";
            approvedBy = null;
          };
          invest-excess = {
            from = "mercury-mirazo";
            to = "public-mirazo";
            rule = {
              aboveUsd = floor;
              keepUsd = floor;
            };
            as = "personal";
            when = "once a strategy is promoted: the nightly ledger proposes Mercury's cash above its floor";
            approvedBy = null;
          };
          top-up-operating = {
            from = "public-mirazo";
            to = "mercury-mirazo";
            rule.refillToUsd = floor;
            as = "personal";
            when = "whenever Mercury personal falls below its floor: the ledger proposes the shortfall";
            approvedBy = null;
          };
        };

    };

    perSystem =
      { pkgs, ... }:
      {
        checks.money-flows = pkgs.runCommand "money-flows" { nativeBuildInputs = [ pkgs.lean4 ]; } ''
          cat ${./_lean/Flows.lean} ${pkgs.writeText "FlowFacts.lean" (builtins.seq config.money.flowsChecked facts)} > Check.lean
          lean Check.lean
          touch $out
        '';
      };
  };
}
