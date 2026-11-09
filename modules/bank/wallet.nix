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
# offers (Mercury and Capital One offer passkeys: each listed in the
# report as a factor to raise). packages.wallet-report lists what is not yet a card: every login,
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
    # A separate entity for now (the owner, 2026-11-08), not yet declared
    # in identity.entities.
    ++ [ "GoFundMe-NonProfit" ]
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

  # An agent holding a card: the governance grant's effects and reason.
  # Spending, destroying and signing in are never among them (Cedar's base
  # layer forbids them whatever a holder says).
  holder = types.submodule {
    options = {
      effects = mkOption {
        type = types.nonEmptyListOf (
          types.enum [
            "read"
            "write"
            "probe"
          ]
        );
      };
      why = mkOption { type = types.str; };
    };
  };

  # Every holder of a card with an account, as (agent, account, card).
  holdings = lib.concatLists (
    lib.mapAttrsToList (
      id: c:
      lib.optionals (c.account != null) (
        lib.mapAttrsToList (agent: h: {
          inherit agent id h;
          inherit (c) account;
        }) c.holders
      )
    ) cfg.cards
  );

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
          type = types.attrsOf holder;
          default = { };
          description = "Agents that may use it, how and why. On a card with an account, each holder is that agent's grant on the account: Cedar's permits are generated from these, and from nothing else.";
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

  # The bank's own cards, written by hand: the accounts that hold money,
  # as Pass holds them today (read 2026-11-08 by title and type only).
  own = {
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
      # The owner, 2026-11-08: the banks confirm by SMS to their phone.
      secondFactor = {
        method = "sms";
        via = "mirazo-identity";
        offered = [
          "passkey"
          "security-key"
          "sms"
        ];
      };
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
      holders.trading-mirazo = {
        effects = [ "read" ];
        why = "paper days: event contracts, quotes and preflights, which place nothing, and their settlement (trading.paper)";
      };
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
      # The owner, 2026-11-08: the banks confirm by SMS to their phone.
      secondFactor = {
        method = "sms";
        via = "mirazo-identity";
        offered = [
          "passkey"
          "sms"
        ];
      };
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
      # The owner, 2026-11-08: the banks confirm by SMS to their phone.
      secondFactor = {
        method = "sms";
        via = "mirazo-identity";
      };
      target = "close";
      why = "closes once no kept bill rests on Chase";
    };
    credit-one-mirazo = {
      type = "login";
      vault = "Mirazo-Root";
      title = "creditonebank.com";
      account = "credit-one-mirazo";
      mint = "human:sign-up";
      # The owner, 2026-11-08: the banks confirm by SMS to their phone.
      secondFactor = {
        method = "sms";
        via = "mirazo-identity";
      };
      target = "close";
      why = "closes once no kept bill rests on it";
    };
    discover-mirazo = {
      type = "login";
      vault = "Mirazo-Root";
      title = "card.discover.com";
      account = "discover-mirazo";
      mint = "human:sign-up";
      # The owner, 2026-11-08: the banks confirm by SMS to their phone.
      secondFactor = {
        method = "sms";
        via = "mirazo-identity";
      };
      why = "its card moved onto Capital One's platform in 2026";
    };
    experian = {
      type = "login";
      vault = "Mirazo-Root";
      title = "Experian";
      account = "experian";
      mint = "human:sign-up";
      # The owner, 2026-11-08: the banks confirm by SMS to their phone.
      secondFactor = {
        method = "sms";
        via = "mirazo-identity";
      };
      target = "keep";
      why = "the credit file";
    };
    paypal-mirazo = {
      type = "login";
      vault = "Mirazo-Root";
      title = "paypal.com";
      account = "paypal-mirazo";
      mint = "human:sign-up";
      # The owner, 2026-11-08: the banks confirm by SMS to their phone.
      secondFactor = {
        method = "sms";
        via = "mirazo-identity";
      };
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
      holders.legal-mirazo = {
        effects = [ "read" ];
        why = "identity documents for the owner's filings";
      };
      target = "keep";
      why = "the owner's one identity card: passport and driver's licence together";
    };
  };

  # Every other held account's login, as the login item it names; replaced
  # by a hand-written card as each is read (its second factor, its URLs).
  handAccounts = lib.unique (
    lib.filter (a: a != null) (
      lib.mapAttrsToList (_: c: if c.type == "login" then c.account else null) own
    )
  );
  heldLogins = lib.mapAttrs' (
    a: h:
    lib.nameValuePair "login-${a}" {
      type = "login";
      vault = entities.${h.owner}.vault;
      title = h.login.item;
      account = a;
      mint = "human:sign-up";
      why = "the login of ${a}";
    }
  ) (lib.filterAttrs (a: _: !(lib.elem a handAccounts)) config.accounts.held);
  # Every legal document, as the note it is attached to (its Proton Drive
  # link), written by the legal team's tools.
  documents = lib.listToAttrs (
    lib.concatLists (
      lib.mapAttrsToList (
        e: r:
        lib.mapAttrsToList (
          d: doc:
          lib.nameValuePair "doc-${e}-${d}" {
            type = "note";
            inherit (doc.where) vault;
            title = doc.where.item;
            mint = "automation:legal-documents";
            holders."legal-${e}" = {
              effects = [ "read" ];
              why = "the legal record it belongs to";
            };
            target = "keep";
            why = doc.title;
          }
        ) (r.documents or { })
      ) config.legal.records
    )
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
    factorWeak = lib.attrNames (
      lib.filterAttrs (
        _: c:
        let
          rank = f: lib.lists.findFirstIndex (x: x == f) 9 factors;
          best = lib.foldl' (m: f: lib.min m (rank f)) 9 c.secondFactor.offered;
        in
        c.secondFactor.method != null && best < rank c.secondFactor.method
      ) cfg.cards
    );
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
      // own
      // heldLogins
      // documents;

    # Wallet step 3 (2026-11-09): agents hold cards. Every governance grant
    # is a holder of the card for its account; no module writes grants.
    governance.agents = lib.mkMerge (
      map (x: {
        ${x.agent}.grants = [
          {
            inherit (x) account;
            inherit (x.h) effects;
            why = "${x.h.why} (holds ${x.id})";
          }
        ];
      }) holdings
    );
    # One card per agent and account: Cedar names each grant by the pair.
    governance.problems = lib.mapAttrsToList (
      k: xs: "wallet: ${k} is held through ${lib.concatMapStringsSep " and " (x: x.id) xs}; hold one card"
    ) (lib.filterAttrs (_: xs: lib.length xs > 1) (lib.groupBy (x: "${x.agent} on ${x.account}") holdings));

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
            -- Logins to raise to their provider's strongest factor (reported).
            #eval weakCards cards
            end Kagamizo.Wallet
          '';
        };
      };
  };
}
