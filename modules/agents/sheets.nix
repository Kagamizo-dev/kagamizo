# The model sheet: a unit of work calls a model only through a typed sheet.
# We run no weights ourselves (the owner, 2026-11-11): every model is a
# provider's, routed through OpenRouter on the account already held, and
# what we build is the harness around its modality. A sheet states what
# goes in, what must come out, how long a run may take and what it may
# cost.
#
#   agents.sheets.<m> = {
#     inputs;      what the harness sends: text, image
#     output;      what must come back: image, svg, mesh, text
#     licence;     whether commercial use is allowed, and the page saying so
#     account;     the held account that pays
#     host; endpoint; model;   the one call the sheet allows
#     perf;        the most a run may take and cost, and the record once
#                  measured (set only by a probe, never by hand)
#     quality;     what the owner or a later unit judges; the harness
#                  itself holds the format
#     status;      declared, probed or live
#   }
#
#   packages.picture    the harness for image and drawing models
#                       (./_picture, Rust): `picture SHEET --prompt-file F
#                       --out DIR [--ref IMAGE]...` makes the one call,
#                       holds the answer to the sheet's time, cost and
#                       format, and publishes each file by its hash with a
#                       manifest; a run over its cost, with no cost
#                       reported, or of the wrong kind publishes nothing
#   checks.agents-sheets  Lean (./_lean/Sheets.lean): every sheet's licence
#                       allows commercial use, its account is held and its
#                       host allowed, a harness exists for its output, and
#                       a live model has a measured record inside its
#                       targets
#
# The call is OpenRouter's POST /api/v1/images as its own OpenAPI states it
# (./_json/openrouter-images.json, read and hashed 2026-11-11; extracted by
# hand, not yet by a catalog extractor: a gap). The first sheets are three
# image models. None is live: no run has been measured, so the targets
# below are ours, not records. A mesh has no harness yet, so no sheet may
# return one.
{ lib, config, ... }:
let
  inherit (lib) mkOption types;
  cfg = config.agents.sheets;
  q = builtins.toJSON;
  url = types.strMatching "https://.+";
  # The session's allowlist, evaluated as ../claude/claude.nix does.
  inherit ((lib.evalModules { modules = [ ../claude/_environment.nix ]; }).config) network;
  allowedHosts = lib.concatLists (
    lib.mapAttrsToList (_: g: lib.optionals (g.enable or true) g.hosts) network.allow
  );

  sheet = types.submodule {
    options = {
      inputs = mkOption {
        type = types.nonEmptyListOf (
          types.enum [
            "text"
            "image"
          ]
        );
      };
      output = mkOption {
        type = types.enum [
          "image"
          "svg"
          "mesh"
          "text"
        ];
      };
      licence = {
        commercialUse = mkOption { type = types.bool; };
        source = mkOption { type = url; };
      };
      account = mkOption { type = types.enum (lib.attrNames config.accounts.held); };
      host = mkOption { type = types.strMatching "([a-z0-9-]+\\.)+[a-z]{2,}"; };
      endpoint = mkOption { type = types.strMatching "/[A-Za-z0-9/_-]*"; };
      model = mkOption { type = types.str; };
      perf = {
        maxSeconds = mkOption { type = types.ints.positive; };
        maxCents = mkOption {
          type = types.ints.positive;
          description = "For one image; a run of several may cost that many times it.";
        };
        record = mkOption {
          type = types.nullOr (
            types.submodule {
              options = {
                seconds = mkOption { type = types.ints.unsigned; };
                cents = mkOption { type = types.ints.unsigned; };
                on = mkOption { type = types.strMatching "[0-9]{4}-[0-9]{2}-[0-9]{2}"; };
              };
            }
          );
          default = null;
        };
      };
      quality = mkOption {
        type = types.str;
        description = "What the owner or a later unit judges of the output.";
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

  reachable = s: lib.elem s.host allowedHosts;

  # What the harness is built with: the one call each sheet allows.
  rendered = lib.mapAttrs (_: s: {
    inherit (s)
      host
      endpoint
      model
      output
      ;
    inherit (s.perf) maxSeconds maxCents;
  }) (lib.filterAttrs (_: s: s.output == "image" || s.output == "svg") cfg);

  facts = ''

    namespace Kagamizo.Agents.Sheets

    def sheets : List Sheet := [${
      lib.concatStringsSep ",\n  " (
        lib.mapAttrsToList (
          n: s:
          "{ name := ${q n}, inputs := [${
            lib.concatMapStringsSep ", " (i: ".${i}") s.inputs
          }], output := .${s.output}, commercial := ${lib.boolToString s.licence.commercialUse}, reachable := ${lib.boolToString (reachable s)}, maxSeconds := ${toString s.perf.maxSeconds}, maxCents := ${toString s.perf.maxCents}, record := ${
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
    licence = {
      commercialUse = true;
      source = "https://openrouter.ai/terms";
    };
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
      concept-image = openrouter "google/gemini-3.1-flash-image" // {
        inputs = [
          "text"
          "image"
        ];
        output = "image";
        perf = {
          maxSeconds = 60;
          maxCents = 10;
        };
        quality = "The owner picks one of the views; nothing is chosen for them";
        why = "Concept views from the owner's words and reference photos; priced by tokens, about 4 to 7 cents an image by our own estimate";
      };
      consistent-view = openrouter "black-forest-labs/flux.2-pro" // {
        inputs = [
          "text"
          "image"
        ];
        output = "image";
        perf = {
          maxSeconds = 60;
          maxCents = 5;
        };
        quality = "Front, back and open views agree on every pocket and mount before a shape is made from them";
        why = "The same design from other sides, from the chosen view as its reference; 3 cents a megapixel";
      };
      line-art = openrouter "recraft/recraft-v4-vector" // {
        inputs = [ "text" ];
        output = "svg";
        perf = {
          maxSeconds = 60;
          maxCents = 10;
        };
        quality = "The drawing reads as the part it names";
        why = "Line art for patterns and labels as SVG; 8 cents an image";
      };
    };

    # The one model call a unit may make, typed (../governance).
    governance.actions.openrouter.image = {
      effect = "spend";
      description = "Generate images through a declared sheet, within its cost and the key's cap";
      command = "picture";
    };

    perSystem =
      { pkgs, config, ... }:
      {
        packages.picture = pkgs.rustPlatform.buildRustPackage {
          pname = "picture";
          version = "0.1.0";
          src = ./_picture;
          cargoLock.lockFile = ./_picture/Cargo.lock;
          PICTURE_SHEETS = pkgs.writeText "picture-sheets.json" (q rendered);
          meta.mainProgram = "picture";
        };
        checks.agents-sheets = config.kagamizo.leanCheck {
          name = "agents-sheets";
          source = ./_lean/Sheets.lean;
          inherit facts;
        };
      };
  };
}
