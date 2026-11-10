# The model sheet: a unit of work calls a model only through a typed sheet
# (the owner's direction, 2026-11-10: type the API, and also the engine and
# the environment around the weights, and hold each to a performance
# standard). A sheet states what the model is, its licence, how it is
# reached, what runs it and what it must achieve.
#
#   agents.sheets.<m> = {
#     task;        what it does: image, image-edit, vector, mesh, chat, embed
#     access;      hosted (the provider runs the weights) or weights (we do)
#     licence;     its id, whether commercial use is allowed, how its hub
#                  gates it, and the page that says so
#     hosted;      the held account, the host, the endpoint and the model id
#     weights;     the hub repository, the revision, every file's sha256,
#                  the engine (a package of this flake's nixpkgs) and its
#                  backend, the variables that switch its telemetry off
#     perf;        the most a run may take and cost, and the record once
#                  measured (set only by a probe, never by hand)
#     quality;     what a run's output must pass before it is published
#     status;      declared, probed or live
#   }
#
# checks.agents-sheets (./_lean/Sheets.lean): every sheet's licence allows
# commercial use, none waits on an author's manual approval, a hosted
# model's account is held and its host allowed, weights are pinned by hash
# and run offline with telemetry off, and a live model has a measured
# record inside its targets.
#
# The first sheets are the image models on the OpenRouter account already
# held (its images endpoint and prices read 2026-11-10). None is live: no
# run has been measured, so the targets below are ours, not records.
{ lib, config, ... }:
let
  inherit (lib) mkOption types;
  cfg = config.agents.sheets;
  q = builtins.toJSON;
  url = types.strMatching "https://.+";
  sha256 = types.strMatching "[0-9a-f]{64}";
  # The session's allowlist, evaluated as ../claude/claude.nix does.
  inherit ((lib.evalModules { modules = [ ../claude/_environment.nix ]; }).config) network;
  allowedHosts = lib.concatLists (
    lib.mapAttrsToList (_: g: lib.optionals (g.enable or true) g.hosts) network.allow
  );

  sheet = types.submodule {
    options = {
      task = mkOption {
        type = types.enum [
          "image"
          "image-edit"
          "vector"
          "mesh"
          "chat"
          "embed"
        ];
      };
      access = mkOption {
        type = types.enum [
          "hosted"
          "weights"
        ];
      };
      licence = {
        id = mkOption {
          type = types.str;
          description = "An SPDX id, the hub's own id, or proprietary-api for a hosted model.";
        };
        commercialUse = mkOption { type = types.bool; };
        gate = mkOption {
          type = types.enum [
            "open"
            "automatic"
            "manual"
          ];
          default = "open";
          description = "How its hub gates the weights; manual is an author's approval with no time bound.";
        };
        source = mkOption { type = url; };
      };
      hosted = mkOption {
        type = types.nullOr (
          types.submodule {
            options = {
              account = mkOption { type = types.enum (lib.attrNames config.accounts.held); };
              host = mkOption { type = types.strMatching "([a-z0-9-]+\\.)+[a-z]{2,}"; };
              endpoint = mkOption { type = types.strMatching "/[A-Za-z0-9/_-]*"; };
              model = mkOption { type = types.str; };
            };
          }
        );
        default = null;
      };
      weights = mkOption {
        type = types.nullOr (
          types.submodule {
            options = {
              repository = mkOption { type = types.strMatching "[A-Za-z0-9._-]+/[A-Za-z0-9._-]+"; };
              revision = mkOption { type = types.strMatching "[0-9a-f]{40}"; };
              files = mkOption { type = types.addCheck (types.attrsOf sha256) (f: f != { }); };
              engine = mkOption {
                type = types.str;
                description = "The nixpkgs package that loads them.";
              };
              backend = mkOption {
                type = types.enum [
                  "cpu"
                  "cuda"
                  "vulkan"
                ];
              };
              offline = mkOption { type = types.bool; };
              telemetryOff = mkOption {
                type = types.attrsOf types.str;
                default = { };
                description = "The variables that switch the engine's telemetry off.";
              };
              telemetry = mkOption {
                type = types.bool;
                description = "The engine reports usage unless told not to.";
              };
            };
          }
        );
        default = null;
      };
      perf = {
        maxSeconds = mkOption { type = types.ints.positive; };
        maxCents = mkOption { type = types.ints.positive; };
        record = mkOption {
          type = types.nullOr (
            types.submodule {
              options = {
                seconds = mkOption { type = types.ints.unsigned; };
                cents = mkOption { type = types.ints.unsigned; };
                on = mkOption { type = types.strMatching "[0-9]{4}-[0-9]{2}-[0-9]{2}"; };
                hardware = mkOption { type = types.str; };
              };
            }
          );
          default = null;
        };
      };
      quality = mkOption {
        type = types.str;
        description = "What a run's output must pass before it is published.";
      };
      status = mkOption {
        type = types.enum [
          "declared"
          "probed"
          "live"
        ];
        default = "declared";
      };
      why = mkOption { type = types.str; };
    };
  };

  reachable = s: s.hosted != null && lib.elem s.hosted.host allowedHosts;
  pinned = s: s.weights != null;
  sealed =
    s:
    s.weights != null && s.weights.offline && (!s.weights.telemetry || s.weights.telemetryOff != { });

  facts = ''

    namespace Kagamizo.Agents.Sheets

    def sheets : List Sheet := [${
      lib.concatStringsSep ",\n  " (
        lib.mapAttrsToList (
          n: s:
          "{ name := ${q n}, access := .${s.access}, commercial := ${lib.boolToString s.licence.commercialUse}, gate := .${s.licence.gate}, reachable := ${lib.boolToString (reachable s)}, pinned := ${lib.boolToString (pinned s)}, sealed := ${lib.boolToString (sealed s)}, maxSeconds := ${toString s.perf.maxSeconds}, maxCents := ${toString s.perf.maxCents}, record := ${
            if s.perf.record == null then
              "none"
            else
              "some { seconds := ${toString s.perf.record.seconds}, cents := ${toString s.perf.record.cents} }"
          }, status := .${s.status} }"
        ) cfg
      )
    }]

    theorem sheets_sound : sound sheets = true := by
      decide +kernel

    end Kagamizo.Agents.Sheets
  '';

  openrouter = model: {
    account = "openrouter";
    host = "openrouter.ai";
    endpoint = "/api/v1/images";
    inherit model;
  };
in
{
  options.agents.sheets = mkOption {
    type = types.attrsOf sheet;
    default = { };
  };

  config = {
    agents.sheets = {
      concept-image = {
        task = "image";
        access = "hosted";
        licence = {
          id = "proprietary-api";
          commercialUse = true;
          source = "https://openrouter.ai/terms";
        };
        hosted = openrouter "google/gemini-3.1-flash-image";
        perf = {
          maxSeconds = 60;
          maxCents = 10;
        };
        quality = "The owner picks one of the views; nothing is chosen for them";
        why = "Concept views from the owner's words and reference photos; priced by tokens, about 4 to 7 cents an image by our own estimate";
      };
      consistent-view = {
        task = "image-edit";
        access = "hosted";
        licence = {
          id = "proprietary-api";
          commercialUse = true;
          source = "https://openrouter.ai/terms";
        };
        hosted = openrouter "black-forest-labs/flux.2-pro";
        perf = {
          maxSeconds = 60;
          maxCents = 5;
        };
        quality = "Front, back and open views agree on every pocket and mount before a shape is made from them";
        why = "The same design from other sides, from the chosen view as its reference; 3 cents a megapixel";
      };
      line-art = {
        task = "vector";
        access = "hosted";
        licence = {
          id = "proprietary-api";
          commercialUse = true;
          source = "https://openrouter.ai/terms";
        };
        hosted = openrouter "recraft/recraft-v4-vector";
        perf = {
          maxSeconds = 60;
          maxCents = 10;
        };
        quality = "The drawing is valid SVG and holds no embedded raster";
        why = "Line art for patterns and labels as SVG; 8 cents an image";
      };
    };

    perSystem =
      { config, ... }:
      {
        checks.agents-sheets = config.kagamizo.leanCheck {
          name = "agents-sheets";
          source = ./_lean/Sheets.lean;
          inherit facts;
        };
      };
  };
}
