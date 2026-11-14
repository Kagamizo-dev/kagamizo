# Where OpenRouter may route each kind of work, from typed expectations
# (the owner's rule of 2026-11-06: routing by declared price and
# performance bounds, every decision explicit). One model is served by many
# providers at prices up to 200x apart and at different speeds; a routing
# class names the most it may pay per kind of token, the precision it
# accepts, and the uptime, time to first token and throughput it needs.
# The endpoints that meet every bound are derived here from two dated
# measurements, ./_spend/prices.json (OpenRouter's endpoint list) and
# ./_json/performance.json (`openrouter probe`: one tiny request pinned to
# each endpoint), and become the class's guardrail: the providers its keys
# may reach. agent-spend holds a job's budget at the same endpoints.
#
#   openrouter.routing.<class> = {
#     model; keys; quantizations;
#     maxUsdPerMillion = { input; cacheRead; output; };
#     minUptimePct; maxFirstTokenMs; minTokensPerSecond;
#   }
#   openrouter.routing.<class>.endpoints   derived: the endpoint tags that pass
#
#   checks.openrouter-routing   Lean (./_lean/Routing.lean): every class has
#                               an endpoint, and every endpoint it allows meets
#                               every one of its bounds
{ lib, config, ... }:
let
  inherit (lib) mkOption types;
  cfg = config.openrouter.routing;
  prices = lib.importJSON ./_spend/prices.json;
  perf = lib.importJSON ./_json/performance.json;
  q = builtins.toJSON;
  # Integers for Lean: micro-dollars per million tokens, tenths of a
  # token per second, hundredths of a percent.
  micro = x: builtins.floor (x * 1000000 + 0.5);
  tenths = x: builtins.floor (x * 10 + 0.5);
  hundredths = x: builtins.floor (x * 100 + 0.5);

  measured = m: tag: lib.findFirst (e: e.tag == tag) null (perf.models.${m} or [ ]);
  quantOf = tag: lib.last ([ "unknown" ] ++ lib.tail (lib.splitString "/" tag));

  passes =
    c: e:
    let
      p = measured c.model e.provider;
    in
    e.input <= c.maxUsdPerMillion.input
    && e.cacheRead <= c.maxUsdPerMillion.cacheRead
    && e.output <= c.maxUsdPerMillion.output
    && lib.elem (quantOf e.provider) c.quantizations
    && p != null
    && p.ok
    && p.uptimePct >= c.minUptimePct
    && p.ttftMs <= c.maxFirstTokenMs
    && p.tokensPerSecond >= c.minTokensPerSecond;

  class = types.submodule (
    { config, ... }:
    {
      options = {
        model = mkOption {
          type = types.enum (lib.attrNames prices.models);
          description = "The model, as priced in ./_spend/prices.json.";
        };
        keys = mkOption {
          type = types.listOf (types.enum (lib.attrNames top.openrouter.keys));
          description = "The keys whose requests this class bounds (its guardrail's assignments).";
        };
        quantizations = mkOption {
          type = types.listOf (
            types.enum [
              "fp4"
              "fp8"
              "bf16"
              "fp16"
              "mxfp4"
              "unknown"
            ]
          );
          description = "The precisions accepted; fp4 trades quality for price, so it is a decision.";
        };
        maxUsdPerMillion = {
          input = mkOption { type = types.numbers.positive; };
          cacheRead = mkOption { type = types.numbers.positive; };
          output = mkOption { type = types.numbers.positive; };
        };
        minUptimePct = mkOption { type = types.numbers.between 0 100; };
        maxFirstTokenMs = mkOption { type = types.ints.positive; };
        minTokensPerSecond = mkOption { type = types.numbers.positive; };
        endpoints = mkOption {
          type = types.listOf types.str;
          readOnly = true;
          default = map (e: e.provider) (lib.filter (passes config) prices.models.${config.model});
          description = "Derived: the endpoint tags (provider/quantization) that meet every bound.";
        };
        providers = mkOption {
          type = types.listOf types.str;
          readOnly = true;
          default = lib.unique (map (t: lib.head (lib.splitString "/" t)) config.endpoints);
          description = "Derived: the providers of those endpoints, the guardrail's allowed providers.";
        };
      };
    }
  );
  top = config;
in
{
  options.openrouter.routing = mkOption {
    type = types.attrsOf class;
    default = { };
    description = "Where each kind of work may be routed, from typed price and performance bounds.";
  };

  config = {
    openrouter.routing.agents = {
      model = config.openrouter.defaultModel;
      keys = [
        # chat-and-code is the owner's playground: every declared model,
        # routed by the workspace's sort, not bound to this class.
        "orca-fleet"
        "research"
        "swarms-jingzo"
        "swarms-mirazo"
        "swarms-kagamizo"
      ];
      quantizations = [ "fp8" ];
      # A cache read at most 4/1000 of a cent per thousand tokens: agent loops
      # are 97% cache reads (openrouter.spend).
      maxUsdPerMillion = {
        input = 0.15;
        cacheRead = 0.004;
        output = 0.7;
      };
      minUptimePct = 98;
      maxFirstTokenMs = 4000;
      minTokensPerSecond = 15;
    };

    perSystem =
      { config, ... }:
      {
        checks.openrouter-routing = config.kagamizo.leanCheck {
          name = "openrouter-routing";
          source = ./_lean/Routing.lean;
          facts = ''

            namespace Kagamizo.Routing
            def classes : List (Class × List Endpoint) := [
            ${lib.concatStringsSep ",\n" (
              lib.mapAttrsToList (
                n: c:
                let
                  allowed = lib.filter (e: lib.elem e.provider c.endpoints) prices.models.${c.model};
                  endpoint =
                    e:
                    let
                      p = measured c.model e.provider;
                    in
                    "{ tag := ${q e.provider}, quant := ${q (quantOf e.provider)}, input := ${toString (micro e.input)}, cacheRead := ${toString (micro e.cacheRead)}, output := ${toString (micro e.output)}, uptime := ${toString (hundredths p.uptimePct)}, ttftMs := ${toString p.ttftMs}, tps := ${toString (tenths p.tokensPerSecond)} }";
                in
                "  ({ name := ${q n}, quants := ${q c.quantizations}, maxInput := ${toString (micro c.maxUsdPerMillion.input)}, maxCacheRead := ${toString (micro c.maxUsdPerMillion.cacheRead)}, maxOutput := ${toString (micro c.maxUsdPerMillion.output)}, minUptime := ${toString (hundredths c.minUptimePct)}, maxTtftMs := ${toString c.maxFirstTokenMs}, minTps := ${toString (tenths c.minTokensPerSecond)} },\n   [${
                    lib.concatMapStringsSep ", " endpoint allowed
                  }])"
              ) cfg
            )}
            ]

            /-- Every class has an endpoint, and every endpoint it allows meets
            every one of its bounds. -/
            theorem routing_holds : classes.all (fun (c, es) => sound c es) = true := by decide
            end Kagamizo.Routing
          '';
        };
      };
  };
}
