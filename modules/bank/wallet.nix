# The wallet: every card the bank holds is a Proton Pass item (the owner's
# vision, 2026-11-08: the bank is a wallet, a card-minting factory; nothing
# exists that is not typed in a card). A card is declared here by its type,
# vault, title and the fields it carries; its values live only in Pass.
#
#   wallet.cards.<id> = { type; template; vault; title; fields; account;
#                         mint; holders; devices; earns; secondFactor; urls;
#                         target; why }
#   wallet.devices.<d> = { kind; why }
#
# Item types and their fields come from the pinned pass-cli
# (../catalog/_json/pass-items.json); vaults are the entities' and the
# infra vaults (../proton/vaults.nix).
#
# checks.bank-wallet (./_lean/Wallet.lean) proves the declared cards are
# unique items (type, vault and title), typed, and that each known second factor is one its provider
# offers. packages.wallet-report lists what is not yet a card: every login,
# Mercury card and legal document the repository names with no card, and
# every login weaker than its provider allows. Modules move onto cards one
# at a time; each move turns its part of the report into a theorem.
{ lib, config, ... }:
let
  inherit (lib) mkOption types;
  cfg = config.wallet;
  q = builtins.toJSON;
  catalog = lib.importJSON ../catalog/_json/pass-items.json;
  inherit (config.identity.checked) entities;
  vaults = lib.unique (
    lib.mapAttrsToList (_: e: e.vault) entities
    ++ lib.attrValues config.proton.infraVaults
    ++ lib.mapAttrsToList (_: e: "${e.vault}-Sessions") entities
  );
  factors = [
    "passkey"
    "security-key"
    "totp"
    "email"
    "sms"
  ];
  leanFactor = f: if f == "security-key" then "securityKey" else f;
  allowedFields =
    c:
    if c.template != null then
      lib.attrNames catalog.appTemplates.${c.template}.fields
    else if c.type == "custom" then
      c.fields
    else
      catalog.types.${c.type}.fields;

  card = types.submodule (
    { name, ... }:
    {
      options = {
        type = mkOption { type = types.enum (lib.attrNames catalog.types); };
        template = mkOption {
          type = types.nullOr (types.enum (lib.attrNames catalog.appTemplates));
          default = null;
        };
        vault = mkOption { type = types.enum vaults; };
        title = mkOption {
          type = types.str;
          default = name;
          description = "The Pass item's title, exactly.";
        };
        fields = mkOption {
          type = types.listOf types.str;
          default = [ ];
          description = "The fields it carries (names only; values stay in Pass).";
        };
        account = mkOption {
          type = types.nullOr (types.enum (lib.attrNames config.accounts.held));
          default = null;
          description = "The held account this card signs in to or pays for.";
        };
        mint = mkOption {
          type = types.strMatching "(human|automation):[a-z0-9-]+";
          description = "Who makes it: a declared human step, or a tool.";
        };
        holders = mkOption {
          type = types.attrsOf (
            types.listOf (
              types.enum [
                "read"
                "write"
                "probe"
              ]
            )
          );
          default = { };
          description = "Agents that may use it, and how (Cedar's grants come from these).";
        };
        devices = mkOption {
          type = types.listOf (
            types.submodule {
              options = {
                device = mkOption { type = types.enum (lib.attrNames cfg.devices); };
                as = mkOption { type = types.enum factors; };
              };
            }
          );
          default = [ ];
        };
        earns = mkOption {
          type = types.bool;
          default = false;
          description = "In the portfolio: a card that brings money in.";
        };
        secondFactor = {
          method = mkOption {
            type = types.nullOr (types.enum factors);
            default = null;
            description = "How the login is confirmed today; null while unread.";
          };
          via = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "The card the code goes to: the phone card for sms, the address card for email.";
          };
          offered = mkOption {
            type = types.listOf (types.enum factors);
            default = [ ];
            description = "What the provider offers, from its own pages.";
          };
        };
        urls = {
          signIn = mkOption {
            type = types.nullOr types.str;
            default = null;
          };
          manage = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "The account-management address.";
          };
        };
        target = mkOption {
          type = types.enum [
            "keep"
            "close"
            "merge"
            "undecided"
          ];
          default = "undecided";
          description = "Its fate in the owner's target wallet.";
        };
        why = mkOption {
          type = types.str;
          default = "";
        };
      };
    }
  );

  # What the repository names today, by vault and title.
  refs =
    lib.mapAttrsToList (a: h: {
      vault = entities.${h.owner}.vault;
      title = h.login.item;
      from = "accounts.held.${a}.login";
    }) config.accounts.held
    ++ lib.mapAttrsToList (n: c: {
      vault = entities.${config.accounts.held.${c.account}.owner}.vault;
      title = "card-${n}";
      from = "mercury.cards.${n}";
    }) config.mercury.cards
    ++ lib.concatLists (
      lib.mapAttrsToList (
        e: r:
        lib.mapAttrsToList (d: doc: {
          inherit (doc.where) vault;
          title = doc.where.item;
          from = "legal.records.${e}.documents.${d}";
        }) (r.documents or { })
      ) config.legal.records
    );

  rendered = lib.mapAttrsToList (
    id: c:
    "{ id := ${q id}, kind := ${q c.type}, vault := ${q c.vault}, title := ${q c.title}, fields := ${q c.fields}, allowed := ${q (allowedFields c)}, factor := ${
      if c.secondFactor.method == null then "none" else "some .${leanFactor c.secondFactor.method}"
    }, offered := [${lib.concatMapStringsSep ", " (f: ".${leanFactor f}") c.secondFactor.offered}] }"
  ) cfg.cards;
  covered = r: lib.any (c: c.vault == r.vault && c.title == r.title) (lib.attrValues cfg.cards);
  report = {
    cards = lib.length (lib.attrNames cfg.cards);
    byType = lib.mapAttrs (_: lib.length) (lib.groupBy (c: c.type) (lib.attrValues cfg.cards));
    uncovered = lib.filter (r: !covered r) refs;
    factorUnknown = lib.attrNames (
      lib.filterAttrs (_: c: c.type == "login" && c.secondFactor.method == null) cfg.cards
    );
    toClose = lib.attrNames (lib.filterAttrs (_: c: c.target == "close") cfg.cards);
    earning = lib.attrNames (lib.filterAttrs (_: c: c.earns) cfg.cards);
  };
in
{
  options.wallet = {
    cards = mkOption {
      type = types.attrsOf card;
      default = { };
    };
    devices = mkOption {
      type = types.attrsOf (
        types.submodule {
          options = {
            kind = mkOption {
              type = types.enum [
                "phone"
                "laptop"
                "pi"
                "security-key"
              ];
            };
            why = mkOption { type = types.str; };
          };
        }
      );
      default = { };
    };
  };

  config = {
    wallet.devices = {
      pixel-9a = {
        kind = "phone";
        why = "the owner's phone: today's passkeys and authenticator codes";
      };
      yoga-c940 = {
        kind = "laptop";
        why = "the desk target (shell.targets.yoga-c940)";
      };
    };

    # Every Mercury card, as the credit-card item `cards vault` writes for
    # it in its account's owner's vault (../mercury/cards.nix): minted by the
    # owner, then vaulted by automation.
    wallet.cards =
      lib.mapAttrs' (
        n: c:
        lib.nameValuePair "mercury-card-${n}" {
          type = "credit-card";
          vault = entities.${config.accounts.held.${c.account}.owner}.vault;
          title = "card-${n}";
          fields = [
            "cardholder_name"
            "number"
            "expiration_date"
            "cvv"
          ];
          inherit (c) account why;
          mint = "human:mint-card";
          target = "keep";
        }
      ) config.mercury.cards
      // {
        mercury-jingzo = {
          type = "login";
          vault = "Jingzo-LLC";
          title = "Mercury";
          account = "mercury-jingzo";
          mint = "human:sign-up";
          secondFactor = {
            method = "passkey";
            offered = [
              "passkey"
              "security-key"
            ];
          };
          devices = [
            {
              device = "pixel-9a";
              as = "passkey";
            }
          ];
          target = "keep";
          why = "Jingzo's treasury; its passkey was registered from the phone";
        };
        mercury-mirazo = {
          type = "login";
          vault = "Mirazo-Root";
          title = "Mercury";
          account = "mercury-mirazo";
          mint = "human:sign-up";
          secondFactor.offered = [
            "passkey"
            "security-key"
          ];
          target = "keep";
          why = "the owner's personal Mercury";
        };
        public-mirazo = {
          type = "login";
          vault = "Mirazo-Root";
          title = "Public";
          account = "public-mirazo";
          mint = "human:sign-up";
          secondFactor.method = "sms";
          earns = true;
          target = "keep";
          why = "the brokerage: every trade; Public offers no security key (its help pages show SMS only)";
        };
        public-api-mirazo = {
          type = "custom";
          template = "api-credential";
          vault = "Mirazo-Root";
          title = "Public";
          fields = [
            "Secret"
            "Permissions"
          ];
          account = "public-mirazo";
          mint = "human:console-credential";
          holders.trading-mirazo = [ "read" ];
          earns = true;
          target = "keep";
          why = "the API credential the trading node reads";
        };
        capital-one-mirazo = {
          type = "login";
          vault = "Mirazo-Root";
          title = "CapitalOne";
          account = "capital-one-mirazo";
          mint = "human:sign-up";
          target = "keep";
          why = "the one outside card in the owner's target wallet";
        };
        capital-one-venture-x = {
          type = "credit-card";
          vault = "Mirazo-Root";
          title = "Capital One - Venture X";
          account = "capital-one-mirazo";
          mint = "human:mint-card";
          target = "keep";
          why = "the Venture X ($10,000 line)";
        };
        chase-mirazo = {
          type = "login";
          vault = "Mirazo-Root";
          title = "Chase";
          account = "chase-mirazo";
          mint = "human:sign-up";
          target = "close";
          why = "closes once no kept bill rests on Chase";
        };
        credit-one-mirazo = {
          type = "login";
          vault = "Mirazo-Root";
          title = "creditonebank.com";
          account = "credit-one-mirazo";
          mint = "human:sign-up";
          target = "close";
          why = "closes once no kept bill rests on it";
        };
        discover-mirazo = {
          type = "login";
          vault = "Mirazo-Root";
          title = "card.discover.com";
          account = "discover-mirazo";
          mint = "human:sign-up";
          why = "its card moved onto Capital One's platform in 2026";
        };
        experian = {
          type = "login";
          vault = "Mirazo-Root";
          title = "Experian";
          account = "experian";
          mint = "human:sign-up";
          target = "keep";
          why = "the credit file";
        };
        paypal-mirazo = {
          type = "login";
          vault = "Mirazo-Root";
          title = "paypal.com";
          account = "paypal-mirazo";
          mint = "human:sign-up";
          why = "PayPal";
        };
        proton = {
          type = "login";
          vault = "Mirazo-Root";
          title = "Proton";
          account = "proton";
          mint = "human:sign-up";
          secondFactor = {
            method = "totp";
            offered = [
              "security-key"
              "totp"
            ];
          };
          target = "keep";
          why = "the account every card lives in; Bridge signs in with its TOTP; a YubiKey would raise it";
        };
        mirazo-identity = {
          type = "identity";
          vault = "Mirazo-Root";
          title = "ID";
          fields = [
            "full_name"
            "birthdate"
            "passport_number"
            "license_number"
          ];
          mint = "human:sign-up";
          holders.legal-mirazo = [ "read" ];
          target = "keep";
          why = "the owner's one identity card: passport and driver's licence together";
        };
      };

    perSystem =
      { config, pkgs, ... }:
      {
        packages.wallet-report = pkgs.writeText "wallet-report.json" (builtins.toJSON report);
        checks.bank-wallet = config.kagamizo.leanCheck {
          name = "bank-wallet";
          source = ./_lean/Wallet.lean;
          facts = ''

            namespace Kagamizo.Wallet
            def cards : List Card := [${lib.concatStringsSep ",\n  " rendered}]
            /-- The declared cards are unique items, typed, with offered factors. -/
            theorem wallet_sound : sound cards = true := by decide
            end Kagamizo.Wallet
          '';
        };
      };
  };
}
