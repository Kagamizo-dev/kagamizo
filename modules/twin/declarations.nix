# The twin world's representations, generated from the repository's declared
# modules, agents, keys and cards so the world always matches what exists.
#
#   twin.representations.<name> every perf-target module gets a building,
#   every governance agent gets a character placed in its area's district,
#   every OpenRouter key and Mercury card gets an item.
#
# The representations are declared here, not hand-written, so adding a module
# or agent automatically adds its twin.
{ lib, config, ... }:
let
  top = config;
  agents = top.governance.agents;
  targets = top.perf.targets;
  keys = top.openrouter.keys;
  cards = top.mercury.cards;
  areas = top.organization.areas;

  # ── sprites ───────────────────────────────────────────────────────────
  # Simple 16×16 pixel sprites over the declared palette. Each string is
  # exactly 16 palette characters. Exactly 16 rows.

  buildingSprite = [
    "0000000000000000"
    "0222222222222220"
    "0211111111111120"
    "0211111111111120"
    "0211144441111120"
    "0211111111111120"
    "0211111111111120"
    "0211111441111120"
    "0211111111111120"
    "0211122222111120"
    "0211111111111120"
    "0211111111111120"
    "0211111111111120"
    "0211111111111120"
    "0222222222222220"
    "0ff0000000000ff0"
  ];

  characterSprite = [
    "0000000000000000"
    "000000ffff000000"
    "0000f22222f00000"
    "000f2222222f0000"
    "000f2222222f0000"
    "0000f22222f00000"
    "000000ffff000000"
    "000000f2f2f00000"
    "0000f22222f00000"
    "000ff22222ff0000"
    "00f222222222f000"
    "00f222222222f000"
    "000ff22222ff0000"
    "00000f222f000000"
    "00000f222f000000"
    "0000ff2222ff0000"
  ];

  coinSprite = [
    "0000000000000000"
    "0000000000000000"
    "000000ffff000000"
    "0000ff2222ff0000"
    "000ff22222ff0000"
    "00ff22222222ff00"
    "00ff22ffff22ff00"
    "00ff22ffff22ff00"
    "00ff22ffff22ff00"
    "00ff22ffff22ff00"
    "00ff22222222ff00"
    "000ff222222ff000"
    "0000ff2222ff0000"
    "000000ffff000000"
    "0000000000000000"
    "0000000000000000"
  ];

  # ── module → district mapping ─────────────────────────────────────────
  # Map each module to a district based on what it does.
  moduleDistrict = {
    tokens = "infra";
    statestore = "infra";
    migration = "infra";
    mailbox = "infra";
    lean = "infra";
    catalog = "infra";
    governance = "agents";
    ci = "infra";
    operations = "home";
    trading = "trading";
    organization = "agents";
    media = "media";
    discord = "media";
    android = "home";
    gamedev = "media";
    compliance = "compliance";
    legal = "legal";
    research = "research";
    public = "money";
    money = "money";
    mercury = "money";
    agents = "agents";
  };

  # ── agent → district ──────────────────────────────────────────────────
  agentDistrict = name:
    let
      serves = agents.${name}.serves;
      agentAreas = areas.${serves} or { };
      # Find the area that owns this agent, default to agents district.
      areaNames = lib.filter (a: agentAreas.${a}.owner == name) (lib.attrNames agentAreas);
      districtOfArea = a:
        if lib.hasPrefix "admin" a then
          "home"
        else if lib.hasPrefix "finance" a || lib.hasPrefix "billing" a then
          "money"
        else if lib.hasPrefix "legal" a then
          "legal"
        else if lib.hasPrefix "research" a then
          "research"
        else if lib.hasPrefix "dev" a then
          "agents"
        else if lib.hasPrefix "automation" a then
          "infra"
        else
          "agents";
    in
    if builtins.length areaNames > 0 then
      districtOfArea (builtins.head areaNames)
    else
      "agents";

  # ── buildings per module ──────────────────────────────────────────────
  moduleNames = lib.unique (map (t: t.module) (lib.attrValues targets));
  buildings = lib.listToAttrs (
    map (
      m:
      let
        dist = moduleDistrict.${m} or "infra";
      in
      lib.nameValuePair "building-${m}" {
        kind = "building";
        of = { module = m; };
        place = dist;
        status = "running";
        sprite = buildingSprite;
        recipes = [ ];
      }
    ) moduleNames
  );

  # ── characters per agent ──────────────────────────────────────────────
  characters = lib.listToAttrs (
    map (
      n:
      lib.nameValuePair "character-${n}" {
        kind = "character";
        of = { team = n; };
        place = agentDistrict n;
        status = "running";
        sprite = characterSprite;
        recipes = [ ];
      }
    ) (lib.attrNames agents)
  );

  # ── items per OpenRouter key ──────────────────────────────────────────
  keyItems = lib.listToAttrs (
    map (
      n:
      lib.nameValuePair "key-${n}" {
        kind = "item";
        of = { asset = "openrouter:${n}"; };
        place = "infra";
        status = "running";
        sprite = coinSprite;
        recipes = [ ];
      }
    ) (lib.attrNames keys)
  );

  # ── items per Mercury card ────────────────────────────────────────────
  cardItems = lib.listToAttrs (
    map (
      n:
      lib.nameValuePair "card-${n}" {
        kind = "item";
        of = { asset = "mercury:${n}"; };
        place = "money";
        status = "running";
        sprite = coinSprite;
        recipes = [ ];
      }
    ) (lib.attrNames cards)
  );

in
{
  config.twin.representations = buildings // characters // keyItems // cardItems;
}