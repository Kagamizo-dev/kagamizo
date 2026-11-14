# What the agents may spend, typed: four tiers from free to dear, every
# kind of task pinned to the cheapest tier that can do it, and the
# OpenRouter keys' caps held within the card that pays them. The owner's
# rule (2026-11-04): a rule or a small quantized model wherever it does the
# job, a paid model only where nothing cheaper will.
#
#   agents.tiers.<name> = { rank; runs; model; why; }
#       rank 0 rule     deterministic code on the host
#       rank 1 small    a small quantized model on the host (llama.cpp)
#       rank 2 flash    DeepSeek V4 Flash on OpenRouter
#       rank 3 pro      DeepSeek V4 Pro, or a vision or GPU model
#   agents.tasks.<kind> = <tier>
#       every kind of work an agent does, and its tier; an agent that wants
#       a higher tier for one task states why, and the reason is logged
#   agents.policyText
#       the policy, as the lead prompt every swarm starts with (../governance/orca.nix)
#
# checks.agents-budget has Lean prove (./_lean/Budget.lean) that no task of
# rank 0 or 1 runs on a paid tier, and that the keys' monthly caps add up to
# no more than the card's monthly allowance.
{ lib, config, ... }:
let
  inherit (lib) mkOption types;
  cfg = config.agents;
  q = builtins.toJSON;
  paid = t: t.runs != "host";

  tier = types.submodule (
    { name, ... }:
    {
      options = {
        rank = mkOption { type = types.ints.between 0 3; };
        runs = mkOption {
          type = types.enum [
            "host"
            "openrouter"
            "gpu"
          ];
          description = "host costs nothing; openrouter and gpu are paid.";
        };
        model = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "For openrouter: one of openrouter.models. For host: the local model's name (../hetzner/_tier1.nix), or null for a rule.";
        };
        why = mkOption { type = types.str; };
        name = mkOption {
          type = types.str;
          default = name;
          readOnly = true;
        };
      };
    }
  );

  # Per month, in whole dollars.
  monthly =
    usd: interval:
    {
      daily = usd * 30;
      weekly = usd * 4;
      monthly = usd;
      yearly = usd / 12;
    }
    .${interval};
  # The card that pays OpenRouter (../openrouter/card.nix).
  card = config.mercury.cards.openrouter;
  cardMonthly = monthly card.limitUsd card.interval;
  keys = lib.mapAttrsToList (n: k: {
    name = n;
    monthlyUsd = monthly k.limitUsd k.reset;
  }) config.openrouter.keys;

  rendered = ''
    namespace Kagamizo.Budget

    /-- Every tier, rendered by modules/agents/tiers.nix. -/
    def tiers : List Tier := [
    ${lib.concatStringsSep ",\n" (
      lib.mapAttrsToList (
        n: t: "  { name := ${q n}, rank := ${toString t.rank}, paid := ${lib.boolToString (paid t)} }"
      ) cfg.tiers
    )}
    ]

    /-- Every kind of task and its tier. -/
    def tasks : List Task := [
    ${lib.concatStringsSep ",\n" (
      lib.mapAttrsToList (
        k: tn:
        let
          t = cfg.tiers.${tn};
        in
        "  { kind := ${q k}, tier := { name := ${q tn}, rank := ${toString t.rank}, paid := ${lib.boolToString (paid t)} } }"
      ) cfg.tasks
    )}
    ]

    /-- The OpenRouter keys' caps, per month. -/
    def keys : List Key := [
    ${lib.concatMapStringsSep ",\n" (
      k: "  { name := ${q k.name}, monthlyUsd := ${toString k.monthlyUsd} }"
    ) keys}
    ]

    /-- Every agent team's share of its key, per month (../governance). -/
    def teams : List Team := [
    ${lib.concatStringsSep ",\n" teams}
    ]

    /-- The paying card's allowance, per month (mercury.cards.openrouter). -/
    def card : Nat := ${toString cardMonthly}

    /-- No task of rank 0 or 1 runs on a paid tier. -/
    theorem tasks_frugal : tasks.all Task.frugal = true := by decide +kernel

    /-- The keys' caps fit the card together ... -/
    theorem keys_within : keysWithin keys card = true := by decide +kernel

    /-- ... so no one key can drain more than the card allows. -/
    theorem each_key_within : ∀ k ∈ keys, k.monthlyUsd ≤ card :=
      within_means_each keys card keys_within

    /-- The teams' shares fit their keys. -/
    theorem teams_within : teamsWithin teams keys = true := by decide +kernel

    end Kagamizo.Budget
  '';

  # Each agent's key: its own, or its entity's swarm key (../governance/orca.nix).
  keyOf = a: if a.key != null then a.key else "swarms-${a.serves}";
  teams = lib.mapAttrsToList (
    n: a: "  { name := ${q n}, key := ${q (keyOf a)}, monthlyUsd := ${toString a.budgetUsdPerMonth} }"
  ) config.governance.agents;
  byRank = lib.sort (a: b: a.rank < b.rank) (lib.attrValues cfg.tiers);
  tasksOf = tn: lib.attrNames (lib.filterAttrs (_: t: t == tn) cfg.tasks);
in
{
  options.agents = {
    tiers = mkOption {
      type = types.attrsOf tier;
      default = { };
    };
    tasks = mkOption {
      type = types.attrsOf (types.enum (lib.attrNames cfg.tiers));
      default = { };
      description = "Every kind of task an agent does, pinned to its tier.";
    };
    policyText = mkOption {
      type = types.str;
      readOnly = true;
      description = "The tier policy as prose, for every agent's prompt.";
    };
    teamsJson = mkOption {
      type = types.str;
      readOnly = true;
      description = "Every agent team as JSON (name, purpose, personas, model, key, budget, tools, classes), for the harness.";
    };
    models = mkOption {
      type = types.attrsOf (
        types.submodule {
          options = {
            repo = mkOption {
              type = types.strMatching "[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+";
              description = "The Hugging Face repository.";
            };
            file = mkOption { type = types.strMatching "[A-Za-z0-9_.-]+\\.gguf"; };
            sha256 = mkOption { type = types.strMatching "[0-9a-f]{64}"; };
            sizeGb = mkOption { type = types.numbers.positive; };
            license = mkOption { type = types.str; };
          };
        }
      );
      default = { };
      description = "Local models a host tier runs, pinned by hash (served by ../hetzner/_tier1.nix).";
    };
  };

  config = {
    agents = {
      # Qwen3-4B-Instruct-2507, Q4_K_M (unsloth's GGUF, 2026-11-04): 2.5 GB,
      # fits the host's 8 GB beside the agents. Qwen3.8 ships no small dense
      # model (Flash-Next is 100 GB).
      models.qwen3-4b-instruct = {
        repo = "unsloth/Qwen3-4B-Instruct-2507-GGUF";
        file = "Qwen3-4B-Instruct-2507-Q4_K_M.gguf";
        sha256 = "3605803b982cb64aead44f6c1b2ae36e3acdb41d8e46c8a94c6533bc4c67e597";
        sizeGb = 2.49;
        license = "Apache-2.0";
      };
      tiers = {
        rule = {
          rank = 0;
          runs = "host";
          why = "deterministic code: rules, statistics, parsers, lookups";
        };
        small = {
          rank = 1;
          runs = "host";
          model = "qwen3-4b-instruct";
          why = "a small quantized model on the host's CPU: classification, extraction, routing";
        };
        flash = {
          rank = 2;
          runs = "openrouter";
          model = "deepseek/deepseek-v4.1-flash";
          why = "the cheap strong model: drafting, code, review, summaries";
        };
        pro = {
          rank = 3;
          runs = "openrouter";
          model = "deepseek/deepseek-v4-pro";
          why = "the dear model: planning, vision, anything the flash tier failed";
        };
      };
      tasks = {
        route = "rule";
        dedupe = "rule";
        parse = "rule";
        price-lookup = "rule";
        classify = "small";
        extract = "small";
        tag = "small";
        triage = "small";
        summarize = "flash";
        draft = "flash";
        code = "flash";
        review = "flash";
        research = "flash";
        plan = "flash";
        vision = "pro";
        design = "flash";
      };
      teamsJson = builtins.toJSON (
        lib.mapAttrs (n: a: {
          inherit (a)
            purpose
            personas
            model
            tools
            changeClasses
            harness
            ;
          key = keyOf a;
          inherit (a) budgetUsdPerMonth;
          # Its contract and its place in the lifecycles (./charters.nix).
          charter = config.agents.charters.${n} or null;
          proposes = lib.attrNames (lib.filterAttrs (_: k: k.proposer == n) config.agents.lifecycle);
          reviews = lib.attrNames (lib.filterAttrs (_: k: lib.elem n k.reviewers) config.agents.lifecycle);
        }) config.governance.agents
      );
      policyText = ''
        Spend as little as the task allows. The tiers, cheapest first:
        ${lib.concatMapStrings (
          t:
          "- ${toString t.rank} ${t.name}${lib.optionalString (t.model != null) " (${t.model})"}, ${
            if paid t then "paid" else "free"
          }: ${t.why}. For: ${lib.concatStringsSep ", " (tasksOf t.name)}.\n"
        ) byRank}
        A task runs on its tier. Going one tier up needs a reason you state
        in your reply, and it is logged; going two up is refused. Your key's
        cap is hard: when `openrouter usage` shows it near, stop and say so
        rather than retry.
      '';
    };

    perSystem =
      { pkgs, ... }:
      let
        problems =
          lib.concatLists (
            lib.mapAttrsToList (
              n: t:
              lib.optional (
                t.runs == "openrouter" && !lib.elem t.model config.openrouter.models
              ) "agents.tiers.${n}: ${toString t.model} is not in openrouter.models"
              ++ lib.optional (
                t.runs == "host" && t.model != null && !(cfg.models ? ${t.model})
              ) "agents.tiers.${n}: no agents.models.${toString t.model}"
            ) cfg.tiers
          )
          ++ lib.optional (
            lib.unique (map (t: t.rank) (lib.attrValues cfg.tiers))
            != map (t: t.rank) (lib.attrValues cfg.tiers)
          ) "agents.tiers: two tiers share a rank";
      in
      {
        checks.agents-budget =
          assert lib.assertMsg (problems == [ ]) (lib.concatStringsSep "
" problems);
          pkgs.runCommand "agents-budget"
            {
              nativeBuildInputs = [ pkgs.lean4 ];
              facts = rendered;
              passAsFile = [ "facts" ];
            }
            ''
              cat ${./_lean/Budget.lean} "$factsPath" > Check.lean
              lean Check.lean
              touch $out
            '';
      };
  };
}
