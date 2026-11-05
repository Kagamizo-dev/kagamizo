# Money moving between held accounts, declared before it moves: who it goes
# from and to, how much (a sum, or a rule for the excess over a threshold),
# what it is between the owners (personal, a contribution, a draw, a
# transfer, a sweep), when, and the owner's dated approval. Public moves no
# money by API (modules/public), so every flow here is the owner's hand;
# the declaration is what the books expect to see.
#
#   money.flows.<name> = { from; to; usd | rule; as; when; approvedBy; }
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
                type = types.ints.positive;
                description = "The flow runs once the source holds more than this.";
              };
              keepUsd = mkOption {
                type = types.ints.unsigned;
                description = "What stays behind; the excess over it moves.";
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
        f.rule != null && f.rule.keepUsd > f.rule.aboveUsd
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
  };

  config = {
    money.flowsChecked =
      assert lib.assertMsg (problems == [ ]) (
        "modules/money/_flows.nix:\n" + lib.concatMapStrings (p: "  - ${p}\n") problems
      );
      cfg;

    # The trading plan (HANDOFF.md, 2026-11-02): a $100 seed into the
    # brokerage after five paper days, and the excess over $100 swept back.
    # Both wait on the owner's dated approval.
    money.flows = {
      public-seed = {
        from = "mercury-mirazo";
        to = "public-mirazo";
        usd = 100;
        as = "personal";
        when = "after five paper days (trading.strategies.<s>.stage = paper, five dated days)";
        approvedBy = null;
      };
      public-sweep = {
        from = "public-mirazo";
        to = "mercury-mirazo";
        rule = {
          aboveUsd = 100;
          keepUsd = 100;
        };
        as = "sweep";
        when = "whenever the brokerage account's cash is above the threshold";
        approvedBy = null;
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
