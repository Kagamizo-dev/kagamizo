# Money, typed for tax: who files what, how every transaction is treated,
# and what is owed when, so a full tax report for any entity and year is a
# build output.
#
#   money.tax.<entity>        how the entity is taxed: an individual, or a
#                             business disregarded into its owner's return
#                             (or taxed as its own), with its residence
#   money.treatment.<cat>     Mercury's own category of a transaction, for
#                             every category its pinned SDK has, mapped to
#                             where it lands on a return (Schedule C's line,
#                             the share deductible) or why it is not a
#                             business expense (./treatment.nix)
#   money.obligations <year>  every form and payment due for that tax year,
#                             with its date and the page that states it
#                             (./obligations.nix)
#
#   nix run .#tax-report -- <entity> <year> <out-dir>
#       reads every Mercury account whose activity lands on the entity's
#       return, through the governed mercury-cli (read actions only), and
#       writes the ledger (hledger journal), each business's Schedule C, the
#       transactions that need a decision and the obligations, into
#       <out-dir>. Nothing is stored: the banks keep the history, the repo
#       keeps the rules (the owner's decision, 2026-11-01). A source that
#       could not be read is named in the report, never left out silently.
#
# ./_lean/Money.lean proves the rules: every category has a treatment,
# every disregarded entity's activity is on its owner's return, and every
# account on a paid plan has a payment (../accounts).
{ lib, config, ... }:
let
  inherit (lib) mkOption types;
  top = config;
  cfg = config.money;
  entities = config.identity.checked.entities;
  categories = (lib.importJSON ../catalog/_json/mercury-api.json).enums.MercuryCategory;
  usState = types.strMatching "US-[A-Z]{2}";

  profile = types.submodule {
    options = {
      classification = mkOption {
        type = types.enum [
          "individual"
          "disregarded"
          "s-corp"
          "partnership"
          "c-corp"
        ];
        description = "How the IRS taxes it: an individual, or a business as its classification has it.";
      };
      owner = mkOption {
        type = types.nullOr (types.enum (lib.attrNames entities));
        default = null;
        description = "For a disregarded entity: whose return its activity is on.";
      };
      residence = mkOption {
        type = types.nullOr (
          types.submodule {
            options = {
              state = mkOption {
                type = types.nullOr usState;
                default = null;
                description = "The state of tax residence, when stated.";
              };
              stateIncomeTax = mkOption {
                type = types.bool;
                description = "Whether that state taxes personal income.";
              };
            };
          }
        );
        default = null;
        description = "For an individual: where they are resident for tax.";
      };
      confirmedBy = mkOption {
        type = types.str;
        description = "Who or what states the classification.";
      };
    };
  };

  treatment = types.submodule {
    options = {
      kind = mkOption {
        type = types.enum [
          "schedule-c"
          "personal"
          "nondeductible"
          "review"
        ];
      };
      line = mkOption {
        type = types.nullOr (types.strMatching "[0-9]+[ab]?");
        default = null;
        description = "Schedule C (Form 1040) Part II line, for schedule-c.";
      };
      percent = mkOption {
        type = types.ints.between 0 100;
        default = 100;
        description = "The share deductible (meals: 50).";
      };
      why = mkOption {
        type = types.str;
        default = "";
      };
    };
  };

  # Whose return an entity's activity is on.
  returnOf =
    e:
    let
      p = cfg.tax.${e};
    in
    if p.classification == "disregarded" then returnOf p.owner else e;

  # The declarations as Lean facts, for ./_lean/Money.lean.
  q = builtins.toJSON;
  camel =
    k:
    lib.concatStrings (
      lib.imap0 (i: w: if i == 0 then w else lib.toUpper (lib.substring 0 1 w) + lib.substring 1 (-1) w) (
        lib.splitString "-" k
      )
    );
  facts = m: ''
    namespace Kagamizo.Money

    def catalogCategories : List String := [${lib.concatMapStringsSep ", " q categories}]

    def treatments : List (String × Treatment) := [
    ${lib.concatStringsSep ",\n" (
      lib.mapAttrsToList (
        c: t:
        "  (${q c}, ${
            if t.kind == "schedule-c" then "(.scheduleC ${q t.line} ${toString t.percent})" else ".${t.kind}"
          })"
      ) m.treatment
    )}
    ]

    def profiles : List Profile := [
    ${lib.concatStringsSep ",\n" (
      lib.mapAttrsToList (
        e: p:
        "  { entity := ${q e}, classification := ${
            if p.classification == "disregarded" then
              "(.disregarded ${q p.owner})"
            else
              ".${camel p.classification}"
          } }"
      ) m.tax
    )}
    ]

    def accounts : List Account := [
    ${lib.concatStringsSep ",\n" (
      lib.mapAttrsToList (
        n: a:
        "  { name := ${q n}, billing := .${
            config.accounts.plans.${a.provider}.${a.plan}.billing.value
          }, paid := ${lib.boolToString (a.payment != null)} }"
      ) config.accounts.held
    )}
    ]

    /-- Every category Mercury's pinned SDK has, has a treatment. -/
    theorem every_category_treated :
        catalogCategories.all (fun c => treatments.any (·.1 == c)) = true := by decide

    /-- No treatment deducts more than the whole cost. -/
    theorem never_over_deducted : treatments.all (·.2.deductible ≤ 100) = true := by decide

    /-- A business meal deducts half. -/
    theorem meals_half : (treatments.lookup "Restaurants").map Treatment.deductible = some 50 := by decide

    /-- Every entity's activity ends on a return someone files. -/
    theorem every_activity_lands : lands profiles = true := by decide

    /-- Every account on a paid plan names what pays it. -/
    theorem every_paid_account_payable : accounts.all Account.payable = true := by decide

    end Kagamizo.Money
  '';

  problems =
    lib.mapAttrsToList (e: _: "money.tax.${e}: say how it is taxed") (
      lib.filterAttrs (e: x: !(cfg.tax ? ${e}) && x.legal.status != "planned") entities
    )
    ++ lib.concatLists (
      lib.mapAttrsToList (
        e: p:
        lib.optional (
          (p.classification == "disregarded") != (p.owner != null)
        ) "money.tax.${e}: `owner` is set exactly for a disregarded entity"
        ++ lib.optional (
          (p.classification == "individual") != (p.residence != null)
        ) "money.tax.${e}: `residence` is set exactly for an individual"
        ++ lib.optional (
          p.classification == "individual" && entities.${e}.kind != "person"
        ) "money.tax.${e}: only a person is taxed as an individual"
      ) cfg.tax
    )
    ++ map (c: "money.treatment: Mercury's category ${c} has no treatment") (
      lib.subtractLists (lib.attrNames cfg.treatment) categories
    )
    ++ map (c: "money.treatment: ${c} is not a category of Mercury's pinned SDK") (
      lib.subtractLists categories (lib.attrNames cfg.treatment)
    )
    ++ lib.concatLists (
      lib.mapAttrsToList (
        id: d:
        lib.optional (
          (d.as == "schedule-c") != (d.line != null)
        ) "money.decisions.${id}: a Schedule C line exactly when as = schedule-c"
      ) cfg.decisions
    )
    ++ lib.concatLists (
      lib.mapAttrsToList (
        c: t:
        lib.optional (
          (t.kind == "schedule-c") != (t.line != null)
        ) "money.treatment.${c}: a Schedule C line exactly when kind = schedule-c"
      ) cfg.treatment
    );
in
{
  imports = [
    ./_treatment.nix
    ./_obligations.nix
    ./_credit.nix
  ];

  options.money = {
    tax = mkOption {
      type = types.attrsOf profile;
      default = { };
    };
    treatment = mkOption {
      type = types.attrsOf treatment;
      default = { };
    };
    decisions = mkOption {
      type = types.attrsOf (
        types.submodule {
          options = {
            as = mkOption {
              type = types.enum [
                "schedule-c"
                "owner-draw"
                "contribution"
                "transfer"
                "gross-receipts"
                "personal"
              ];
            };
            line = mkOption {
              type = types.nullOr (types.strMatching "[0-9]+[ab]?");
              default = null;
            };
            percent = mkOption {
              type = types.ints.between 0 100;
              default = 100;
            };
            why = mkOption { type = types.str; };
            decided = mkOption { type = types.strMatching "[0-9]{4}-[0-9]{2}-[0-9]{2}"; };
          };
        }
      );
      default = { };
      description = ''
        The owner's decision on one transaction, by Mercury's transaction id
        (no amount or name: this repo is public), for what its category
        cannot settle.
      '';
    };
    returnOf = mkOption {
      type = types.functionTo types.str;
      readOnly = true;
      default = returnOf;
      description = "The entity whose return carries an entity's activity.";
    };
    checked = mkOption {
      type = types.raw;
      readOnly = true;
      description = "money, after every rule above holds.";
    };
    creditLinesChecked = mkOption {
      type = types.raw;
      readOnly = true;
    };
  };

  config.perSystem =
    { pkgs, config, ... }:
    let
      money = top.money.checked;
      held = top.accounts.held;
      returns = lib.unique (map money.returnOf (lib.attrNames money.tax));
      years = lib.range 2024 2030;
      # Every Mercury account whose activity lands on a return.
      accountsOf =
        r:
        lib.mapAttrs
          (_: a: {
            entity = a.owner;
            inherit (entities.${a.owner}) legalName;
            personal = a.plan == "personal";
          })
          (
            lib.filterAttrs (
              _: a:
              a.provider == "mercury"
              && a.status == "active"
              && money.tax ? ${a.owner}
              && money.returnOf a.owner == r
            ) held
          );
      rules = lib.genAttrs returns (r: {
        "return" = r;
        accounts = accountsOf r;
        inherit (money) treatment decisions;
        obligations = lib.genAttrs (map toString years) (
          y: lib.filter (o: money.returnOf o.entity == r || o.entity == r) (money.obligations (lib.toInt y))
        );
      });
      rulesJson = pkgs.writeText "money-rules.json" (builtins.toJSON rules);
      report = pkgs.rustPlatform.buildRustPackage {
        pname = "money-report";
        version = "0.1.0";
        src = ./_src;
        cargoLock.lockFile = ./_src/Cargo.lock;
        meta.mainProgram = "money-report";
      };
    in
    {
      packages = {
        money-report = report;
        money-rules = rulesJson;
        tax-report = pkgs.writeShellApplication {
          name = "tax-report";
          runtimeInputs = [
            report
            config.packages.mercury-cli
            pkgs.hledger
            pkgs.jq
            pkgs.coreutils
          ];
          text = ''
            entity=''${1:?usage: tax-report ENTITY YEAR OUT-DIR}
            year=''${2:?usage: tax-report ENTITY YEAR OUT-DIR}
            out=''${3:?usage: tax-report ENTITY YEAR OUT-DIR}
            returns=${lib.escapeShellArg (builtins.toJSON (lib.genAttrs (lib.attrNames money.tax) money.returnOf))}
            ret=$(jq -r --arg e "$entity" '.[$e] // empty' <<<"$returns")
            [ -n "$ret" ] || { echo "tax-report: $entity has no money.tax profile" >&2; exit 2; }
            work=$(mktemp -d)
            trap 'rm -rf "$work"' EXIT
            sources=()
            unread='[]'
            for acc in $(jq -r --arg r "$ret" '.[$r].accounts | keys[]' ${rulesJson}); do
              if mercury-cli --account "$acc" transactions list --start "$year-01-01" --end "$year-12-31" \
                --format jsonl >"$work/$acc.jsonl" 2>"$work/$acc.err"; then
                sources+=("$acc=$work/$acc.jsonl")
              else
                unread=$(jq --arg s "Mercury $acc" --arg w "$(tail -n 1 "$work/$acc.err")" '. + [{source: $s, why: $w}]' <<<"$unread")
              fi
            done
            # The brokerages: their history is not parsed into the ledger yet.
            unread=$(jq '. + [{source: "Public (public-mirazo)", why: "trades, dividends and interest are not read into the ledger yet; take Form 1099-B/DIV/INT from Public"}]' <<<"$unread")
            jq --arg r "$ret" --arg y "$year" --argjson u "$unread" \
              '.[$r] | . + {year: ($y | tonumber), obligations: (.obligations[$y] // []), unread: $u}' \
              ${rulesJson} >"$work/rules.json"
            money-report "$work/rules.json" "$out" "''${sources[@]}"
            LANG=C.UTF-8 hledger -f "$out/ledger.journal" check >/dev/null
            echo "tax-report: $out/README.md"
          '';
        };
      };
      checks = {
        money-report = report;
        # The report end to end, from stand-in transactions.
        money-report-run =
          pkgs.runCommand "money-report-run"
            {
              nativeBuildInputs = [
                report
                pkgs.hledger
              ];
            }
            ''
              cat > biz.jsonl <<'J'
              {"id":"a","amount":-12.5,"status":"sent","kind":"debitCardTransaction","counterpartyName":"Hetzner","mercuryCategory":"Software","postedAt":"2026-02-01T00:00:00Z","createdAt":"2026-02-01T00:00:00Z"}
              {"id":"b","amount":100,"status":"sent","kind":"incomingDomesticWire","counterpartyName":"Someone","createdAt":"2026-03-01T00:00:00Z"}
              J
              money-report ${./_src/_test/rules.json} out biz=biz.jsonl
              LANG=C.UTF-8 hledger -f out/ledger.journal check
              grep -q "| 18 | 12.50 |" out/schedule-c.md
              grep -q "Someone" out/review.md
              touch $out
            '';
        money-lean = pkgs.runCommand "money-lean" { nativeBuildInputs = [ pkgs.lean4 ]; } ''
          cat ${./_lean/Money.lean} ${pkgs.writeText "Facts.lean" (facts money)} > Check.lean
          lean Check.lean
          touch $out
        '';
      };
    };

  config.money = {
    # The owner's answers, 2026-11-01, on what the 2026 report could not
    # settle by category.
    decisions =
      let
        nav = {
          as = "schedule-c";
          line = "27a";
          why = "Nav: business credit for QSearch LLC";
          decided = "2026-11-01";
        };
      in
      {
        "3e790b18-ea89-11f0-8f2c-37bad8b45988" = nav;
        "8e988de6-0152-11f1-b6bd-7b8946967030" = nav;
        "885fd92a-1755-11f1-98dd-bffe2032812e" = nav;
        "7eed8d40-be9b-11f1-a15d-cfbf517e1ad9" = {
          as = "transfer";
          why = "funding QSearch LLC's own Interactive Brokers account";
          decided = "2026-11-01";
        };
        "e03ecdd8-c04a-11f1-a0ae-f7500c27c024" = {
          as = "owner-draw";
          why = "paid to the owner from their disregarded LLC";
          decided = "2026-11-01";
        };
        "f678bb64-cda5-11f1-af36-db0bbda5b4c7" = {
          as = "transfer";
          why = "from the owner's own checking account at another bank";
          decided = "2026-11-01";
        };
      };

    checked =
      assert lib.assertMsg (problems == [ ]) (
        "modules/money:\n" + lib.concatMapStrings (p: "  - ${p}\n") problems
      );
      cfg;

    # The owner's statements, 2026-11-01: resident in a state with no
    # personal income tax; QSearch LLC is theirs alone and never elected
    # otherwise, so the IRS disregards it (its activity is on their 1040).
    tax = {
      mirazo = {
        classification = "individual";
        residence.stateIncomeTax = false;
        confirmedBy = "the owner, 2026-11-01 (state not named)";
      };
      jingzo = {
        classification = "disregarded";
        owner = "mirazo";
        confirmedBy = "the owner, 2026-11-01: single member, no election filed";
      };
    };
  };
}
