# What the CLI's credential may call, per endpoint of Mercury's API
# (../catalog/_json/mercury-api.json), with the evidence for each. The CLI
# signs in with Mercury's own OAuth client and the scopes
# "offline_access openid read write" (internal/auth/oauth.go, OAuthScopes);
# Mercury documents no per-endpoint scopes for it, only token tiers
# (docs.mercury.com/docs/getting-started.md, "Token Permission Tiers"):
#
#   Read Only       "Can fetch all available data on your Mercury account."
#   Read and Write  "Can initiate transactions without admin approval, and
#                   manage recipients."
#   Custom          "Can only perform requests on the specific scopes granted"
#                   (RequestSendMoney named as one).
#
# So every endpoint is in one state for the OAuth session:
#
#   observed   called with it, and it answered (date)
#   tier       the documented tier that covers it, read as applying to the
#              OAuth scopes of the same name: an inference, stated as one
#   refused    called with it, and Mercury refused (date, error code)
#   unknown    neither documented nor observed
#
# mercury-cli runs a command only if every endpoint it calls is observed or
# tier; evaluation fails if an endpoint of the pinned API has no state.
{ lib, config, ... }:
let
  inherit (lib) mkOption types;
  api = lib.importJSON ../catalog/_json/mercury-api.json;

  observed = date: what: {
    state = "observed";
    evidence = "${date}: ${what}";
  };
  tier = name: {
    state = "tier";
    evidence = "token tier ${name} (docs/getting-started.md)";
  };
  refused = date: code: {
    state = "refused";
    evidence = "${date}: ${code}";
  };
  unknown = why: {
    state = "unknown";
    evidence = why;
  };
  readTier = tier "Read Only: fetch all available data";
  transactions = tier "Read and Write: initiate transactions";
  recipients = tier "Read and Write: manage recipients";

  oauth = {
    "accounts.get" = readTier;
    "accounts.list" = observed "2026-10-23" "mercury-cli accounts list, mercury-jingzo";
    "cards.get" = readTier;
    "cards.list" = observed "2026-10-24" "cards plan, mercury-jingzo";
    # Mercury's Vault API: "Available for agentic cards only".
    "cards.reveal" = readTier;
    "cards.new" =
      refused "2026-10-24" "403 tokenNotAuthorized, POST /cards (mercury-jingzo, debit, virtual, $5/monthly)";
    "cards.update" = unknown "card management is in no documented tier; cards.new was refused";
    "cards.freeze" = unknown "card management is in no documented tier; cards.new was refused";
    "cards.unfreeze" = unknown "card management is in no documented tier; cards.new was refused";
    "cards.cancel" = unknown "card management is in no documented tier; cards.new was refused";
    "categories.list" = readTier;
    "categories.new" = unknown "expense categories are in no documented write tier";
    "categories.update" = unknown "expense categories are in no documented write tier";
    "categories.delete" = unknown "expense categories are in no documented write tier";
    "credit.list" = readTier;
    "customers.get" = readTier;
    "customers.list" = readTier;
    "customers.new" = unknown "receivables (customers) are in no documented write tier";
    "customers.update" = unknown "receivables (customers) are in no documented write tier";
    "customers.delete" = unknown "receivables (customers) are in no documented write tier";
    "events.get" = readTier;
    "events.list" = readTier;
    "invoices.get" = readTier;
    "invoices.list" = readTier;
    "invoices.download" = readTier;
    "invoices.attachments.get" = readTier;
    "invoices.attachments.list" = readTier;
    "invoices.new" = unknown "invoicing is in no documented write tier";
    "invoices.update" = unknown "invoicing is in no documented write tier";
    "invoices.cancel" = unknown "invoicing is in no documented write tier";
    "onboarding.apply" = unknown "opening an account; excluded from mercury-cli";
    "org.get" = readTier;
    # The SDK's payments.get/list are request-send-money requests.
    "payments.get" = readTier;
    "payments.list" = readTier;
    "payments.new" = transactions;
    "payments.transfer" = transactions;
    "payments.request" =
      unknown "documented as the Custom scope RequestSendMoney; not that it is in OAuth's write";
    "recipients.get" = readTier;
    "recipients.list" = readTier;
    "recipients.new" = recipients;
    "recipients.update" = recipients;
    "recipients.delete" = recipients;
    "recipients.attachments.list" = readTier;
    "recipients.attachments.attach" =
      unknown "recipient attachments: not said to be part of managing recipients";
    "recipients.invites.list" = readTier;
    "recipients.invites.new" = unknown "recipient invites: not said to be part of managing recipients";
    "recipients.invites.delete" =
      unknown "recipient invites: not said to be part of managing recipients";
    "safes.get" = readTier;
    "safes.list" = readTier;
    "safes.download" = readTier;
    "statements.accounts.list" = readTier;
    "statements.download" = readTier;
    "statements.treasury.list" = readTier;
    "transactions.get" = readTier;
    "transactions.list" = readTier;
    "transactions.update" =
      unknown "editing a transaction's notes or category is in no documented tier";
    "transactions.attachments.attach" = unknown "transaction attachments are in no documented tier";
    "treasury.list" = readTier;
    "treasury.transactions" = readTier;
    "users.get" = readTier;
    "users.list" = observed "2026-10-24" "mercury-cli users list, mercury-jingzo";
    "webhooks.get" = readTier;
    "webhooks.list" = readTier;
    "webhooks.new" = unknown "webhooks are in no documented write tier";
    "webhooks.update" = unknown "webhooks are in no documented write tier";
    "webhooks.delete" = unknown "webhooks are in no documented write tier";
    "webhooks.verify" = unknown "webhooks are in no documented write tier";
  };

  endpoints = lib.attrNames api.endpoints;
  problems =
    map (e: "${e}: an endpoint of the pinned API with no authorization state") (
      lib.filter (e: !(oauth ? ${e})) endpoints
    )
    ++ map (e: "${e}: not an endpoint of the pinned API") (
      lib.filter (e: !(lib.elem e endpoints)) (lib.attrNames oauth)
    );
  runnable =
    s:
    lib.elem s.state [
      "observed"
      "tier"
    ];
  # SDK calls as the CLI's handlers name them (Cards.New, Accounts.ListAutoPaging)
  # to endpoint keys (cards.new, accounts.list).
  endpointOf =
    call:
    let
      key = lib.toLower (lib.replaceStrings [ "AutoPaging" ] [ "" ] call);
    in
    if api.endpoints ? ${key} then
      key
    else
      throw "modules/mercury/authorization.nix: ${call} is no endpoint";
in
{
  options.mercury = {
    authorization = mkOption {
      type = types.attrsOf (types.attrsOf types.str);
      readOnly = true;
      description = "Per endpoint: whether the CLI's OAuth session may call it, and the evidence.";
    };
    commandEndpoints = mkOption {
      type = types.attrsOf (types.listOf types.str);
      readOnly = true;
      description = "Per CLI command: the endpoints its handler calls.";
    };
    blocked = mkOption {
      type = types.attrsOf types.str;
      readOnly = true;
      description = "Per CLI command mercury-cli refuses: why (an endpoint not observed or tier).";
    };
  };

  config.mercury = {
    authorization =
      assert lib.assertMsg (problems == [ ]) (
        "modules/mercury/authorization.nix:\n" + lib.concatStringsSep "\n" problems
      );
      oauth;
    commandEndpoints = lib.mapAttrs (_: c: lib.unique (map endpointOf c.calls)) api.commands;
    blocked = lib.filterAttrs (_: v: v != "") (
      lib.mapAttrs (
        _: eps:
        lib.concatMapStringsSep "; " (e: "${e} is ${oauth.${e}.state} (${oauth.${e}.evidence})") (
          lib.filter (e: !(runnable oauth.${e})) eps
        )
      ) config.mercury.commandEndpoints
    );
  };
}
