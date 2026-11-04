# The physical twin's ledger: what the owner has, where it is, what it cost
# and when it runs low. The schema is public and typed here; the items are
# private, one document in the owner's vault kept by statestore (its write
# protocol never loses a generation, modules/statestore/_lean/Store.lean),
# never in this repository (the owner's decision, project.decisions.
# inventory-store).
#
#   nix run .#inventory -- list [--category C] [--place P] [--json]
#   nix run .#inventory -- show <id> | low [--json]
#   nix run .#inventory -- add <id> --name N --category C --place P
#       [--qty Q] [--unit U] [--acquired YYYY-MM-DD] [--cost AMOUNT CUR]
#       [--source ACCOUNT] [--reorder-at R] [--tag T ...]
#   nix run .#inventory -- move <id> <place> | use <id> <qty>
#       | restock <id> <qty> | remove <id>
#
# Reads ask governance-authorize for proton:inventory-read, writes for
# proton:inventory-write, on the account whose vault holds the document.
# Quantities are whole hundredths, as ./_lean/Inventory.lean proves `use`,
# `restock` and `low` over. INVENTORY_STORE=<file> runs the same commands on
# a local stand-in instead of the vault (checks.inventory-tests does).
{ lib, config, ... }:
let
  inherit (lib) mkOption types;
  cfg = config.inventory;
  q = builtins.toJSON;
  strs = xs: "&[${lib.concatMapStringsSep ", " q xs}]";
  vaults = lib.attrValues config.proton.infraVaults ++ config.proton.vaults;
  entities = lib.attrNames config.identity.checked.entities;

  lean = ''
    namespace Kagamizo.Inventory

    def categories : List String := ${q cfg.categories}
    def places : List String := ${q cfg.places}
    def currencies : List String := ${q cfg.currencies}

    theorem schema_well_formed :
        wellFormed categories && wellFormed places && wellFormed currencies = true := by decide +kernel

    end Kagamizo.Inventory
  '';

  rust = ''
    pub const CATEGORIES: &[&str] = ${strs cfg.categories};
    pub const PLACES: &[&str] = ${strs cfg.places};
    pub const CURRENCIES: &[&str] = ${strs cfg.currencies};
    pub const OWNERS: &[&str] = ${strs entities};
    pub const SOURCES: &[&str] = ${strs (lib.attrNames config.accounts.held)};
    pub const VAULT: &str = ${q cfg.vault};
    pub const NAME: &str = ${q cfg.name};
    pub const ACCOUNT: &str = ${q cfg.account};
  '';
in
{
  options.inventory = {
    categories = mkOption { type = types.listOf (types.strMatching "[a-z][a-z0-9-]*"); };
    places = mkOption {
      type = types.listOf (types.strMatching "[a-z][a-z0-9-]*");
      description = "Where things are kept; a closed set, so a typo fails.";
    };
    currencies = mkOption { type = types.listOf (types.strMatching "[A-Z]{3}"); };
    vault = mkOption {
      type = types.enum vaults;
      description = "The vault holding the items' document.";
    };
    account = mkOption {
      type = types.enum (lib.attrNames config.accounts.held);
      description = "The account that vault belongs to: what reads and writes are authorized on.";
    };
    name = mkOption {
      type = types.strMatching "[a-z][a-z0-9-]*";
      description = "The document's statestore name.";
    };
  };

  config = {
    inventory = {
      categories = [
        "device"
        "tool"
        "part"
        "material"
        "consumable"
        "food"
        "supplement"
        "clothing"
        "document"
        "furniture"
      ];
      places = [
        "carry"
        "home"
        "storage"
        "office"
        "lab"
        "in-transit"
        "lent"
      ];
      currencies = [
        "USD"
        "BRL"
        "EUR"
        "JPY"
        "CNY"
        "GBP"
        "MXN"
        "ARS"
      ];
      vault = config.proton.infraVaults.root;
      account = "proton";
      name = "inventory";
    };

    governance.actions.proton = {
      inventory-read = {
        effect = "read";
        description = "The owner's inventory: items, places, what runs low";
        command = "inventory list";
      };
      inventory-write = {
        effect = "write";
        description = "Add, move, use, restock or remove an inventory item";
        command = "inventory add";
      };
    };

    perSystem =
      { pkgs, config, ... }:
      let
        facts = pkgs.writeText "inventory-facts.rs" rust;
        bin = pkgs.rustPlatform.buildRustPackage {
          pname = "inventory";
          version = "0.1.0";
          src = ./_src;
          cargoLock.lockFile = ./_src/Cargo.lock;
          INVENTORY_FACTS = facts;
          meta.mainProgram = "inventory";
        };
        inventory = pkgs.writeShellApplication {
          name = "inventory";
          runtimeInputs = [
            config.packages.statestore
            config.packages.governance-authorize
            config.packages.pass-cli
          ];
          text = ''
            export PROTON_PASS_KEY_PROVIDER=''${PROTON_PASS_KEY_PROVIDER:-fs}
            exec ${lib.getExe bin} "$@"
          '';
        };
      in
      {
        packages.inventory = inventory;
        checks = {
          inventory-lean =
            pkgs.runCommand "inventory-lean"
              {
                nativeBuildInputs = [ pkgs.lean4 ];
                facts = lean;
                passAsFile = [ "facts" ];
              }
              ''
                cat ${./_lean/Inventory.lean} "$factsPath" > Check.lean
                lean Check.lean
                touch $out
              '';
          inventory-tests = bin.overrideAttrs (_: {
            doCheck = true;
          });
          # The CLI end to end on a stand-in store: no vault, no sign-in.
          inventory-run = pkgs.runCommand "inventory-run" { nativeBuildInputs = [ bin ]; } ''
            export INVENTORY_STORE=$PWD/store
            refused() { if "$@" 2>/dev/null; then echo "accepted, should refuse: $*" >&2; exit 1; fi; }
            inventory add creatine --name "Creatine monohydrate 300 g" --category supplement \
              --place home --qty 300 --unit g --cost 89.90 BRL --reorder-at 60 --tag daily
            inventory add printer --name "Bambu A1 mini" --category device --place lab
            inventory use creatine 250
            inventory low | grep -q creatine
            refused inventory use creatine 100
            refused inventory add bad --name x --category nonsense --place home
            refused inventory add bad --name x --category food --place home --qty -1
            refused inventory add creatine --name again --category food --place home
            inventory move printer storage
            inventory list --place storage | grep -q printer
            inventory restock creatine 300
            inventory show creatine --json | grep -q '"qty":350,'
            inventory remove printer
            refused inventory show printer
            touch $out
          '';
        };
      };
  };
}
