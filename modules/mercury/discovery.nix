# The cards as Mercury last listed them, committed (./_json/cards.json) so
# the declarations (mercury.cards) are checked against a record, not only
# against a live session: `cards [--account A] discover` rewrites A's
# entries from `mercury cards list`, keeping only what the books need (id,
# nickname, status, account, limit, period, merchant lock, kind, agentic;
# never the number, CVC or expiry). The file is typed here from the pinned
# Mercury API catalog (Card, CardSpendLimit, their enums), and
# `checks.cards-declared` has Lean compare the two (./_lean/Cards.lean):
# every declared card is live with its declared limit and period, and every
# live `kagamizo/*` card is declared. Until the first discovery is
# committed (discovered = {}), the comparison is vacuous and says so.
{ lib, config, ... }:
let
  inherit (lib) mkOption types;
  api = lib.importJSON ../catalog/_json/mercury-api.json;
  file = ./_json/cards.json;
  stored = lib.importJSON file;
  card = api.types.Card.fields;
  intervals = [
    "daily"
    "weekly"
    "monthly"
    "yearly"
  ];
  mercuryAccounts = lib.attrNames (
    lib.filterAttrs (_: a: a.provider == "mercury") config.accounts.held
  );

  # The fields `cards discover` keeps, each a field of the catalog's Card.
  kept = [
    "id"
    "nickname"
    "status"
    "kind"
    "isAgentCard"
  ];
  entry = types.submodule {
    options = {
      id = mkOption { type = types.str; };
      nickname = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
      status = mkOption { type = types.enum api.enums.CardStatus; };
      kind = mkOption { type = types.enum api.enums.CardKind; };
      isAgentCard = mkOption {
        type = types.bool;
        default = false;
      };
      account = mkOption {
        type = types.enum mercuryAccounts;
        description = "The held account it was listed on.";
      };
      limitCents = mkOption {
        type = types.nullOr types.ints.unsigned;
        default = null;
        description = "spendLimit.amountCents; null under budgets.";
      };
      period = mkOption {
        type = types.nullOr (types.enum intervals);
        default = null;
        description = "spendLimit.interval.";
      };
      merchantLock = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "merchantLock.name.";
      };
    };
  };
  discovery = types.submodule {
    options = {
      discovered = mkOption {
        type = types.attrsOf (types.strMatching "[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z");
        default = { };
        description = "Per account: when its entries were last listed.";
      };
      cards = mkOption {
        type = types.listOf entry;
        default = [ ];
      };
    };
  };
  problems = map (f: "cards discover keeps `${f}`, which is no field of the pinned API's Card") (
    lib.filter (f: !(card ? ${f})) (
      kept
      ++ [
        "spendLimit"
        "merchantLock"
        "accountId"
      ]
    )
  );
in
{
  options.mercury.discovered = mkOption {
    type = discovery;
    readOnly = true;
    description = "./_json/cards.json, typed.";
  };

  config = {
    mercury.discovered =
      assert lib.assertMsg (problems == [ ]) (
        "modules/mercury/discovery.nix:\n" + lib.concatStringsSep "\n" problems
      );
      stored;

    governance.actions.mercury.cards-discover = {
      effect = "read";
      description = "Record the live cards' ids, limits and locks into the repo";
      command = "cards discover";
    };

    perSystem =
      { pkgs, ... }:
      let
        q = builtins.toJSON;
        opt = v: if v == null then "none" else "some ${q v}";
        declared = lib.mapAttrs (
          name: c: c // { nickname = if c.nickname == null then "kagamizo/${name}" else c.nickname; }
        ) config.mercury.cards;
        d = config.mercury.discovered;
        facts = ''
          namespace Kagamizo.Mercury

          def declared : List Declared := [
          ${lib.concatStringsSep ",\n" (
            lib.mapAttrsToList (
              n: c:
              "  { name := ${q n}, nickname := ${q c.nickname}, account := ${q c.account}, limitCents := ${toString (c.limitUsd * 100)}, period := ${q c.interval}, merchantLock := ${opt c.merchantLock} }"
            ) declared
          )}
          ]

          def discovery : Discovery := {
            accounts := [${lib.concatMapStringsSep ", " q (lib.attrNames d.discovered)}],
            cards := [
          ${lib.concatMapStringsSep ",\n" (
            c:
            "    { nickname := ${opt c.nickname}, account := ${q c.account}, status := ${q c.status}, limitCents := ${opt c.limitCents}, period := ${opt c.period}, merchantLock := ${opt c.merchantLock} }"
          ) d.cards}
            ]
          }

          /-- Every declared card on a discovered account is live, at its limit and period. -/
          theorem declared_live : discovery.declaredLive declared = true := by decide

          /-- Every live kagamizo/* card is declared. -/
          theorem live_declared : discovery.liveDeclared declared = true := by decide

          end Kagamizo.Mercury
        '';
      in
      {
        checks.cards-declared = pkgs.runCommand "cards-declared" { nativeBuildInputs = [ pkgs.lean4 ]; } ''
          cat ${./_lean/Cards.lean} ${pkgs.writeText "CardFacts.lean" facts} > Check.lean
          lean Check.lean
          ${
            if d.discovered == { } then
              ''echo "cards-declared: no discovery committed yet (modules/mercury/_json/cards.json); run cards discover"''
            else
              ''echo "cards-declared: ${toString (lib.length d.cards)} live cards against ${toString (lib.length (lib.attrNames declared))} declared"''
          }
          touch $out
        '';
      };
  };
}
