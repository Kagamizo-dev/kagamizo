# Public's HTTP API as the Rust client is bound to it. The client's table
# (../trading/_rust/public/api-endpoints.json, read at compile time) names
# every endpoint with its method, path, the CLI command it is and that
# command's effect, and the endpoints each client bound may call: reader
# (every trade-run command but place) and placer (place: the reader's and
# the single-leg order). The client refuses any request outside its bound.
#
#   checks.public-api-bound   Lean (./_lean/Endpoints.lean), over the table,
#                             public.endpoints and public.authorization
#                             (./authorization.nix, which checks.public-
#                             endpoints holds against the pinned client) and
#                             governance.actions.public:
#     - the table is exactly the declared endpoints, method and path alike;
#     - every endpoint is a governance action with the same effect, and a
#       command whose handler calls it;
#     - exactly the three order endpoints spend, and only cancel writes;
#     - the reader neither writes nor spends; the placer adds place_order and cancel_order
#       alone; every endpoint either may call is observed or documented.
{ lib, config, ... }:
let
  table = lib.importJSON ../trading/_rust/public/api-endpoints.json;
  key = n: e: "${e.group}.${n}";
  inherit (config.public) endpoints authorization commandEndpoints;
  actions = config.governance.actions.public;
  q = builtins.toJSON;
  list = xs: "[${lib.concatStringsSep ",\n  " xs}]";
  keyOf = lib.mapAttrs key table.endpoints;
  bound = b: map (n: keyOf.${n}) table.clients.${b}.endpoints;
  rendered = lib.mapAttrs' (
    n: e:
    lib.nameValuePair (key n e) "{ name := ${q (key n e)}, method := ${q (lib.toLower e.method)}, path := ${q e.path}, command := ${q e.command}, effect := .${e.effect} }"
  ) table.endpoints;
in
{
  perSystem =
    { config, ... }:
    {
      checks.public-api-bound = config.kagamizo.leanCheck {
        name = "public-api-bound";
        source = ./_lean/Endpoints.lean;
        facts = ''

          namespace Kagamizo.PublicApi
          def table : List Endpoint := ${
            # In the declaration's order: by group.function.
            list (map (k: rendered.${k}) (lib.sort lib.lessThan (lib.attrNames rendered)))
          }
          def declared : List Declared := ${
            list (
              lib.mapAttrsToList (
                k: e:
                "{ name := ${q k}, method := ${q e.method}, path := ${q e.path}, state := ${q authorization.${k}.state} }"
              ) endpoints
            )
          }
          def actions : List Action := ${
            list (
              lib.mapAttrsToList (
                _: a: "{ command := ${q (lib.removePrefix "public " a.description)}, effect := .${a.effect} }"
              ) actions
            )
          }
          def calls : List (String × List String) := ${
            list (lib.mapAttrsToList (c: eps: "(${q c}, ${q eps})") commandEndpoints)
          }
          def reader : List String := ${q (bound "reader")}
          def placer : List String := ${q (bound "placer")}

          set_option maxRecDepth 100000

          /-- The client's table is the declared endpoints, method and path alike. -/
          theorem table_is_declared : sameAs table declared = true := by decide +kernel

          /-- Every endpoint is a typed governance action, effect for effect,
          and a command whose handler calls it. -/
          theorem endpoints_typed : typed actions table = true ∧ called calls table = true := by
            decide +kernel

          /-- Exactly the three order endpoints spend; only cancel writes. -/
          theorem only_orders_spend :
              ofEffect .spend table = ["order_placement.place_multileg_order", "order_placement.place_order", "order_placement.replace_order"] ∧
              ofEffect .write table = ["order_placement.cancel_order"] := by decide +kernel

          /-- The reader neither writes nor spends, and every endpoint either
          bound may call has evidence it answers this account. -/
          theorem bounds_are_safe :
              readOnly table reader = true ∧ runnable declared placer = true := by decide +kernel

          /-- The placer is the reader, the single-leg order and its cancel,
          nothing else: it can end a working order it placed, never replace
          one or place a multi-leg order. -/
          theorem placer_adds_order_and_cancel :
              beyond placer reader = ["order_placement.cancel_order", "order_placement.place_order"] ∧ beyond reader placer = [] := by
            decide +kernel
          end Kagamizo.PublicApi
        '';
      };
    };
}
