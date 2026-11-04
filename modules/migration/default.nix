# Leaving a provider, typed: what each retiring account holds, where each
# kind of data goes, how it is moved and checked, what depends on the
# account, and whether it may close.
#
#   migration.sources.<account> = {
#     classes.<class> = { export; destination; verify; state; };
#     dependants = [ { kind; what; movedTo; done; } ];
#     closed;
#   }
#
# An account in accounts.held with status "retiring" must have a source here
# (../accounts), and a source may be `closed` only when every class is
# verified and every dependant moved: checked here and proven by
# ./_lean/Migration.lean (`checks.migration`). Every provider's full copy is
# kept whole in Proton Drive under /Archives/<provider>; structured data goes
# into the Proton app it belongs in.
{ lib, config, ... }:
let
  inherit (lib) mkOption types;
  cfg = config.migration;
  held = config.accounts.held;
  humanSteps = lib.attrNames config.operations.humanSteps;

  classNames = [
    "mail"
    "contacts"
    "calendars"
    "photos"
    "files"
    "notes"
    "reminders"
    "passwords"
    "passkeys"
    "totp"
    "health"
    "messages"
    "subscriptions"
    "purchases"
    "statements"
    "transactions"
    "archive"
  ];
  destinations = [
    "proton-mail"
    "proton-contacts"
    "proton-calendar"
    "proton-drive"
    "proton-pass"
    "ledger" # modules/money's tax report
    "inventory" # declarations: accounts, subscriptions, credit lines
    "re-declared" # not moved: each login is declared anew (epic 5)
    "nowhere" # deliberately left behind, with why
  ];
  states = [
    "declared"
    "exported"
    "imported"
    "verified"
  ];

  dataClass = types.submodule {
    options = {
      export = mkOption {
        type = types.str;
        description = "How it is read out: a pinned tool's command, or `human:<step>`.";
      };
      destination = mkOption { type = types.enum destinations; };
      verify = mkOption {
        type = types.str;
        description = "How the copy is checked against the source.";
      };
      state = mkOption {
        type = types.enum states;
        default = "declared";
      };
    };
  };

  dependant = types.submodule {
    options = {
      kind = mkOption {
        type = types.enum [
          "login" # another account signs in with this one's address
          "autopay" # a bill drawn from it
          "deposit" # money paid into it
          "2fa" # codes or keys it receives
          "subscription" # a service it pays for or holds
        ];
      };
      what = mkOption { type = types.str; };
      movedTo = mkOption {
        type = types.str;
        description = "Where it goes: a declared account, card or address.";
      };
      done = mkOption {
        type = types.bool;
        default = false;
      };
    };
  };

  source = types.submodule {
    options = {
      product = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "When only one product of the account is left (Chase's checking): its name; the account itself stays.";
      };
      classes = mkOption { type = types.attrsOf dataClass; };
      dependants = mkOption {
        type = types.listOf dependant;
        default = [ ];
      };
      closed = mkOption {
        type = types.bool;
        default = false;
        description = "The account is closed at the provider (human:close-account).";
      };
    };
  };

  problems = lib.concatLists (
    lib.mapAttrsToList (
      name: s:
      lib.optional (!(held ? ${name})) "migration.sources.${name}: no such account in accounts.held"
      ++ lib.optional (
        held ? ${name} && s.product == null && held.${name}.status != "retiring"
      ) "migration.sources.${name}: the account is not `retiring` (or name the `product` that is)"
      ++ map (c: "migration.sources.${name}.classes.${c}: not a data class") (
        lib.subtractLists classNames (lib.attrNames s.classes)
      )
      ++ lib.concatLists (
        lib.mapAttrsToList (
          c: x:
          let
            step = lib.removePrefix "human:" x.export;
          in
          lib.optional (lib.hasPrefix "human:" x.export && !(lib.elem step humanSteps))
            "migration.sources.${name}.classes.${c}.export: ${step} is not a human step (operations.humanSteps)"
        ) s.classes
      )
      ++ lib.optional (
        s.closed && !(lib.all (x: x.state == "verified") (lib.attrValues s.classes))
      ) "migration.sources.${name}: closed before every class is verified"
      ++ lib.optional (
        s.closed && !(lib.all (d: d.done) s.dependants)
      ) "migration.sources.${name}: closed before every dependant moved"
    ) cfg.sources
  );

  q = builtins.toJSON;
  camel =
    k:
    lib.concatStrings (
      lib.imap0 (i: w: if i == 0 then w else lib.toUpper (lib.substring 0 1 w) + lib.substring 1 (-1) w) (
        lib.splitString "-" k
      )
    );
  facts = ''
    namespace Kagamizo.Migration

    def declared : List Source := [
    ${lib.concatStringsSep ",\n" (
      lib.mapAttrsToList (
        n: s:
        "  { account := ${q n}, closed := ${lib.boolToString s.closed}, classes := [${
            lib.concatStringsSep ", " (
              lib.mapAttrsToList (c: x: "(${q c}, .${x.state}, .${camel x.destination})") s.classes
            )
          }], dependants := [${
            lib.concatMapStringsSep ", " (
              d: "{ kind := ${q d.kind}, done := ${lib.boolToString d.done} }"
            ) s.dependants
          }] }"
      ) cfg.sources
    )}
    ]

    /-- No declared account is closed before it is emptied. -/
    theorem declared_closable : declared.all Source.closedRightly = true := by decide

    end Kagamizo.Migration
  '';
in
{
  options.migration = {
    sources = mkOption {
      type = types.attrsOf source;
      default = { };
    };
    checked = mkOption {
      type = types.raw;
      readOnly = true;
    };
  };

  config = {
    migration.checked =
      assert lib.assertMsg (problems == [ ]) (
        "modules/migration:\n" + lib.concatMapStrings (p: "  - ${p}\n") problems
      );
      cfg;

    perSystem =
      { pkgs, ... }:
      {
        packages.migration-facts = pkgs.writeText "Facts.lean" facts;
        checks.migration =
          builtins.seq config.migration.checked pkgs.runCommand "migration"
            { nativeBuildInputs = [ pkgs.lean4 ]; }
            ''
              cat ${./_lean/Migration.lean} ${pkgs.writeText "Facts.lean" facts} > Check.lean
              lean Check.lean
              touch $out
            '';
      };
  };
}
