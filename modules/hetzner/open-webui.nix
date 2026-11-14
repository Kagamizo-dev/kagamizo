# Open WebUI on jingzo-host, typed and bounded (the owner's request,
# 2026-11-06). ./_json/open-webui-catalog.json is the pinned version's own
# configuration surface, read from its source (open-webui/open-webui
# v0.12.2, backend/open_webui/config.py and env.py): 878 variables and 115
# ENABLE_ switches with their defaults, the image engines it supports, and
# what it does not do (no video generation). ./_json/open-webui-decisions.json
# decides every switch, on or off, with a reason; none is left to a default
# nobody read.
#
#   openWebui.environment   the variables jingzo-host's Open WebUI runs with:
#                           every decided switch plus the declared settings
#
# Bounds (checks.open-webui, ./_lean/OpenWebUI.lean): every switch in the
# catalog is decided; nothing runs code on the host or installs packages
# (functions, tools, plugins, pip, tool servers off); the admin screens
# cannot override the code (persistent config off); nothing signs up or
# calls home; and every variable set is one the version reads, or a
# declared library variable. Upgrading Open WebUI is a new catalog from
# the new version's source, so a new switch arrives undecided and fails.
{ lib, config, ... }:
let
  inherit (lib) mkOption types;
  catalog = lib.importJSON ./_json/open-webui-catalog.json;
  decisions = lib.importJSON ./_json/open-webui-decisions.json;
  cfg = config.openWebui;

  # Never on: each runs code outside the repo, overrides it, or reaches out.
  mustBeOff = [
    "ENABLE_FUNCTIONS"
    "ENABLE_TOOLS"
    "ENABLE_PLUGINS"
    "ENABLE_PIP_INSTALL_FRONTMATTER_REQUIREMENTS"
    "ENABLE_TOOL_SERVERS"
    "ENABLE_DIRECT_CONNECTIONS"
    "ENABLE_PERSISTENT_CONFIG"
    "ENABLE_COMMUNITY_SHARING"
    "ENABLE_VERSION_UPDATE_CHECK"
    "ENABLE_SIGNUP"
    "ENABLE_OAUTH_SIGNUP"
    "ENABLE_INITIAL_ADMIN_SIGNUP"
  ];

  known = catalog.variables ++ lib.attrNames catalog.libraryVariables;

  # Every ENABLE_ variable the source reads is a switch to decide, except a
  # deprecated alias read only as the fallback for a newer, decided one.
  catalogSwitches = lib.unique (
    lib.attrNames catalog.switches
    ++ lib.filter (v: lib.hasPrefix "ENABLE_" v && !(catalog.aliases ? ${v})) catalog.variables
  );
  switchEnv = lib.mapAttrs (_: d: if d.on then "True" else "False") decisions;

  q = builtins.toJSON;
  list = xs: "[${lib.concatMapStringsSep ", " q xs}]";
  facts = ''

    namespace Kagamizo.OpenWebUI

    -- The version reads every variable in the catalog: a long literal list.
    set_option maxRecDepth 100000

    def catalogSwitches : List String := ${list catalogSwitches}

    def decidedOn : List String := ${list (lib.attrNames (lib.filterAttrs (_: d: d.on) decisions))}

    def decided : List String := ${list (lib.attrNames decisions)}

    def mustBeOff : List String := ${list mustBeOff}

    def known : List String := ${list known}

    def set : List String := ${list (lib.attrNames cfg.environment)}

    theorem bounded : bounds catalogSwitches decided decidedOn mustBeOff known set = true := by decide +kernel

    end Kagamizo.OpenWebUI
  '';
in
{
  options.openWebui = {
    settings = mkOption {
      type = types.attrsOf types.str;
      default = { };
      description = "Open WebUI's non-switch variables for jingzo-host; each must be one the version reads.";
    };
    environment = mkOption {
      type = types.attrsOf types.str;
      readOnly = true;
      description = "Every decided switch plus the settings: what the host's Open WebUI runs with.";
    };
  };

  config = {
    openWebui.environment = switchEnv // cfg.settings;

    # The host's settings: the models come from OpenRouter (the key arrives
    # in /run/agents/openrouter.env) and the host's free tier 1, and Access
    # signs the owner in by header, which only cloudflared on the loopback
    # can set.
    openWebui.settings =
      let
        inherit (config.hetzner.host.agents) zone tier1Port;
      in
      {
        OPENAI_API_BASE_URLS = "https://openrouter.ai/api/v1;http://127.0.0.1:${toString tier1Port}/v1";
        WEBUI_URL = "https://agents.${zone}";
        WEBUI_AUTH_TRUSTED_EMAIL_HEADER = "Cf-Access-Authenticated-User-Email";
        ANONYMIZED_TELEMETRY = "False";
        DO_NOT_TRACK = "True";
        SCARF_NO_ANALYTICS = "True";
      };

    perSystem =
      { config, ... }:
      {
        checks.open-webui = config.kagamizo.leanCheck {
          name = "open-webui";
          source = ./_lean/OpenWebUI.lean;
          inherit facts;
        };
      };
  };
}
