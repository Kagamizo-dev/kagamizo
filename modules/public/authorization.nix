# What the personal secret may call, per endpoint of Public's API as the
# pinned CLI's generated client names it (publicdotcom_cli/_generated/api,
# one module per endpoint), with the evidence for each. Public documents
# no scopes: an access token minted from the personal secret can call
# everything (../public/account.nix, scopedSecrets = false), so the only
# evidence that an endpoint answers this account is having called it.
#
#   observed    called with it, and it answered (date, by what)
#   documented  listed on Public's API docs; never called from here
#   refused     called with it, and Public refused (date, error)
#   unknown     neither documented nor observed
#
# `brokerage` runs a command only if every endpoint it calls is observed or
# documented; evaluation fails if an endpoint has no state, and
# `checks.public-endpoints` holds this list against the pinned client: every
# endpoint it generates is declared here, with its method and URL template,
# and nothing is declared that it does not have.
#
# Which endpoints a command calls is read off the CLI's own handlers
# (cli.py, each command's `_call`); every authenticated command first mints
# or refreshes its token (authorization.create_personal_access_token).
{ lib, ... }:
let
  inherit (lib) mkOption types;
  catalog = lib.importJSON ../catalog/_json/public.json;

  observed = date: what: {
    state = "observed";
    evidence = "${date}: ${what}";
  };
  documented = {
    state = "documented";
    evidence = "https://public.com/api/docs, never called from here";
  };
  # refused and unknown, when one is seen, are `{ state = "refused"; evidence = "<date>: <error>"; }`
  # and `{ state = "unknown"; evidence = "<why>"; }`.

  # key = <api module>.<function>, as the generated client lays them out.
  endpoints = {
    "authorization.create_personal_access_token" = {
      method = "post";
      path = "/userapiauthservice/personal/access-tokens";
      auth = observed "2026-11-04" "every brokerage and trade command mints its token here";
    };
    "list_accounts.get_accounts" = {
      method = "get";
      path = "/userapigateway/trading/account";
      auth = observed "2026-11-04" "brokerage accounts list: 5OI41709 BROKERAGE, 5OD75475 ROTH_IRA, 2OP05949 ENTITY";
    };
    "account_details.get_account_portfolio_v2" = {
      method = "get";
      path = "/userapigateway/trading/{account_id}/portfolio/v2";
      auth = observed "2026-11-04" "brokerage --json portfolio show: the brokerage account, cash 0.00, no positions, no orders";
    };
    "account_details.get_history" = {
      method = "get";
      path = "/userapigateway/trading/{account_id}/history";
      auth = observed "2026-11-04" "brokerage --json history list: the brokerage account, no transactions yet";
    };
    "instrument_details.get_all_instruments" = {
      method = "get";
      path = "/userapigateway/trading/instruments";
      auth = documented;
    };
    "instrument_details.get_instrument" = {
      method = "get";
      path = "/userapigateway/trading/instruments/{symbol}/{type_}";
      auth = documented;
    };
    "instrument_details.search_bonds" = {
      method = "get";
      path = "/userapigateway/trading/instruments/bonds";
      auth = documented;
    };
    "market_data.get_bars_v2" = {
      method = "get";
      path = "/userapigateway/historicdata/{type_}/{symbol}/{period}";
      auth = observed "2026-11-04" "trade bars (the adapter's bars, modules/trading)";
    };
    "market_data.get_bars_v2_with_aggregation" = {
      method = "get";
      path = "/userapigateway/historicdata/{type_}/{symbol}/{period}/{aggregation}";
      auth = observed "2026-11-04" "trade bars (the adapter names the aggregation)";
    };
    "market_data.get_bond_details" = {
      method = "get";
      path = "/userapigateway/marketdata/{account_id}/bond-details/{symbol}";
      auth = documented;
    };
    "market_data.get_event_contract_bars" = {
      method = "get";
      path = "/userapigateway/historicdata/event-contracts/{event_id}/bars/{period}";
      auth = documented;
    };
    "market_data.get_option_chain" = {
      method = "post";
      path = "/userapigateway/marketdata/{account_id}/option-chain";
      auth = observed "2026-11-04" "trade propose spy-agents (the adapter's option_chain)";
    };
    "market_data.get_option_expirations" = {
      method = "post";
      path = "/userapigateway/marketdata/{account_id}/option-expirations";
      auth = observed "2026-11-04" "trade propose spy-agents (the adapter's option_expirations)";
    };
    "market_data.get_quotes" = {
      method = "post";
      path = "/userapigateway/marketdata/{account_id}/quotes";
      auth = observed "2026-11-04" "trade propose weather-rules (the adapter's quotes)";
    };
    "option_details.get_option_greeks" = {
      method = "get";
      path = "/userapigateway/option-details/{account_id}/greeks";
      auth = documented;
    };
    "option_details.get_strategy_quote" = {
      method = "post";
      path = "/userapigateway/option-details/{account_id}/strategy-details/quote";
      auth = documented;
    };
    "event_contracts.get_event_categories" = {
      method = "get";
      path = "/userapigateway/eventcontract/summary/categories";
      auth = observed "2026-11-04" "brokerage event-contracts categories";
    };
    "event_contracts.get_event_details" = {
      method = "get";
      path = "/userapigateway/eventcontract/details/{event_symbol}";
      auth = documented;
    };
    "event_contracts.get_event_summary" = {
      method = "post";
      path = "/userapigateway/eventcontract/summary";
      auth = observed "2026-11-04" "trade propose weather-rules (the adapter's event_contract_summary)";
    };
    "order_placement.preflight_single_leg" = {
      method = "post";
      path = "/userapigateway/trading/{account_id}/preflight/single-leg";
      auth = observed "2026-11-04" "trade paper (the adapter's preflight; places nothing)";
    };
    "order_placement.preflight_multi_leg" = {
      method = "post";
      path = "/userapigateway/trading/{account_id}/preflight/multi-leg";
      auth = documented;
    };
    "order_placement.place_order" = {
      method = "post";
      path = "/userapigateway/trading/{account_id}/order";
      auth = documented;
    };
    "order_placement.place_multileg_order" = {
      method = "post";
      path = "/userapigateway/trading/{account_id}/order/multileg";
      auth = documented;
    };
    "order_placement.replace_order" = {
      method = "put";
      path = "/userapigateway/trading/{account_id}/order";
      auth = documented;
    };
    "order_placement.cancel_order" = {
      method = "delete";
      path = "/userapigateway/trading/{account_id}/order/{order_id}";
      auth = documented;
    };
    "order_placement.get_order" = {
      method = "get";
      path = "/userapigateway/trading/{account_id}/order/{order_id}";
      auth = documented;
    };
    "order_placement.search_orders" = {
      method = "post";
      path = "/userapigateway/trading/{account_id}/order/search";
      auth = observed "2026-11-04" "brokerage --json order search: the brokerage account, no orders in 30 days";
    };
    "tax_lot_selling.get_unrealized_tax_lots" = {
      method = "get";
      path = "/userapigateway/trading/{account_id}/taxlots/unrealized";
      auth = documented;
    };
    "tax_lot_selling.get_unrealized_tax_lots_csv" = {
      method = "get";
      path = "/userapigateway/trading/{account_id}/taxlots/csv/unrealized";
      auth = documented;
    };
    "tax_lot_selling.get_unrealized_tax_lots_for_symbol" = {
      method = "get";
      path = "/userapigateway/trading/{account_id}/taxlots/unrealized/{symbol}";
      auth = documented;
    };
  };

  token = "authorization.create_personal_access_token";
  # Per command, the endpoints its handler calls besides the token; a
  # command with none works on the CLI's own config file and calls nothing.
  calls = {
    "accounts list" = [ "list_accounts.get_accounts" ];
    "accounts set-default" = [ ];
    "accounts get-default" = [ ];
    "accounts clear-default" = [ ];
    "auth login" = [ ];
    "auth refresh" = [ ];
    "auth status" = [ ];
    "auth logout" = [ ];
    "event-contracts categories" = [ "event_contracts.get_event_categories" ];
    "event-contracts details" = [ "event_contracts.get_event_details" ];
    "event-contracts summary" = [ "event_contracts.get_event_summary" ];
    # With --aggregation the longer path, else the shorter.
    "historicdata bars" = [
      "market_data.get_bars_v2"
      "market_data.get_bars_v2_with_aggregation"
    ];
    "historicdata event-contract-bars" = [ "market_data.get_event_contract_bars" ];
    "history list" = [ "account_details.get_history" ];
    "instruments bonds" = [ "instrument_details.search_bonds" ];
    "instruments get" = [ "instrument_details.get_instrument" ];
    "instruments list" = [ "instrument_details.get_all_instruments" ];
    "market bond-details" = [ "market_data.get_bond_details" ];
    "market option-chain" = [ "market_data.get_option_chain" ];
    "market option-expirations" = [ "market_data.get_option_expirations" ];
    "market quotes" = [ "market_data.get_quotes" ];
    "options greeks" = [ "option_details.get_option_greeks" ];
    "options strategy-quote" = [ "option_details.get_strategy_quote" ];
    "order cancel" = [ "order_placement.cancel_order" ];
    "order get" = [ "order_placement.get_order" ];
    # A deprecated alias of `order get`, the same handler.
    "order get-v2" = [ "order_placement.get_order" ];
    "order place" = [ "order_placement.place_order" ];
    "order place-multileg" = [ "order_placement.place_multileg_order" ];
    "order preflight-multi" = [ "order_placement.preflight_multi_leg" ];
    "order preflight-single" = [ "order_placement.preflight_single_leg" ];
    "order replace" = [ "order_placement.replace_order" ];
    "order search" = [ "order_placement.search_orders" ];
    "portfolio show" = [ "account_details.get_account_portfolio_v2" ];
    "taxlots csv" = [ "tax_lot_selling.get_unrealized_tax_lots_csv" ];
    "taxlots list" = [ "tax_lot_selling.get_unrealized_tax_lots" ];
    "taxlots symbol" = [ "tax_lot_selling.get_unrealized_tax_lots_for_symbol" ];
  };
  # `auth login` and `auth refresh` mint a token and nothing else; every
  # other call refreshes one first.
  minting = [
    "auth login"
    "auth refresh"
  ];
  commandEndpoints = lib.mapAttrs (
    c: eps:
    if lib.elem c minting then
      [ token ]
    else if eps == [ ] then
      [ ]
    else
      eps ++ [ token ]
  ) calls;

  known = lib.attrNames catalog.commands;
  names = lib.attrNames endpoints;
  problems =
    map (c: "${c}: a command of the pinned CLI whose endpoints are not declared") (
      lib.filter (c: !(calls ? ${c})) known
    )
    ++ map (c: "${c}: not a command of the pinned CLI") (
      lib.filter (c: !(lib.elem c known)) (lib.attrNames calls)
    )
    ++ lib.concatLists (
      lib.mapAttrsToList (
        c: eps:
        map (e: "${c}: calls ${e}, which is no declared endpoint") (lib.filter (e: !(endpoints ? ${e})) eps)
      ) calls
    )
    ++ map (e: "${e}: no command calls it") (
      lib.filter (e: e != token && !(lib.any (eps: lib.elem e eps) (lib.attrValues calls))) names
    )
    ++ map (e: "${e}: an endpoint with no authorization state") (
      lib.filter (
        e:
        !(lib.elem endpoints.${e}.auth.state [
          "observed"
          "documented"
          "refused"
          "unknown"
        ])
      ) names
    );
  runnable =
    s:
    lib.elem s.state [
      "observed"
      "documented"
    ];
  authorization = lib.mapAttrs (_: e: e.auth) endpoints;
in
{
  options.public = {
    endpoints = mkOption {
      type = types.attrsOf (
        types.submodule {
          options = {
            method = mkOption {
              type = types.enum [
                "get"
                "post"
                "put"
                "delete"
              ];
            };
            path = mkOption { type = types.strMatching "/.+"; };
          };
        }
      );
      readOnly = true;
      description = "Every endpoint of the pinned client: its method and URL template.";
    };
    authorization = mkOption {
      type = types.attrsOf (types.attrsOf types.str);
      readOnly = true;
      description = "Per endpoint: whether the personal secret is known to call it, and the evidence.";
    };
    commandEndpoints = mkOption {
      type = types.attrsOf (types.listOf types.str);
      readOnly = true;
      description = "Per CLI command: the endpoints its handler calls.";
    };
    blocked = mkOption {
      type = types.attrsOf types.str;
      readOnly = true;
      description = "Per CLI command brokerage refuses: why (an endpoint not observed or documented).";
    };
  };

  config.public = {
    endpoints =
      assert lib.assertMsg (problems == [ ]) (
        "modules/public/authorization.nix:\n" + lib.concatStringsSep "\n" problems
      );
      lib.mapAttrs (_: e: { inherit (e) method path; }) endpoints;
    inherit authorization commandEndpoints;
    blocked = lib.filterAttrs (_: v: v != "") (
      lib.mapAttrs (
        _: eps:
        lib.concatMapStringsSep "; " (
          e: "${e} is ${authorization.${e}.state} (${authorization.${e}.evidence})"
        ) (lib.filter (e: !(runnable authorization.${e})) eps)
      ) commandEndpoints
    );
  };

  config.perSystem =
    { pkgs, config, ... }:
    {
      # The declaration against the pinned client: the same endpoints, each
      # with the method and URL template its generated module states.
      checks.public-endpoints =
        pkgs.runCommand "public-endpoints"
          {
            declared = builtins.toJSON (lib.mapAttrs (_: e: { inherit (e) method path; }) endpoints);
            passAsFile = [ "declared" ];
          }
          ''
            ${pkgs.python3}/bin/python3 -I - "$declaredPath" \
              ${config.packages.public}/${pkgs.python3.sitePackages}/publicdotcom_cli/_generated/api <<'PY'
            import json, os, re, sys
            declared = json.load(open(sys.argv[1]))
            found = {}
            for group in sorted(os.listdir(sys.argv[2])):
                d = os.path.join(sys.argv[2], group)
                if not os.path.isdir(d):
                    continue
                for f in sorted(os.listdir(d)):
                    if not f.endswith(".py") or f == "__init__.py":
                        continue
                    text = open(os.path.join(d, f)).read()
                    m = re.search(r'"method": "([a-z]+)"', text)
                    u = re.search(r'"url": "([^"]+)"', text)
                    if m and u:
                        found[f"{group}.{f[:-3]}"] = {"method": m.group(1), "path": u.group(1)}
            problems = [f"{k}: generated by the pinned client, not declared" for k in found if k not in declared]
            problems += [f"{k}: declared, but the pinned client generates no such endpoint" for k in declared if k not in found]
            problems += [
                f"{k}: declared {declared[k]['method']} {declared[k]['path']}, the client has {found[k]['method']} {found[k]['path']}"
                for k in declared if k in found and declared[k] != found[k]
            ]
            if problems:
                sys.exit("modules/public/authorization.nix:\n" + "\n".join(problems))
            print(f"{len(found)} endpoints, declared as generated")
            PY
            touch $out
          '';
    };
}
