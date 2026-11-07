# The owner's media pipeline, first half: a typed catalog of the action
# camera's clips and a deterministic indexer and renderer. Footage reaches
# the host (another module's hop, Proton Drive to
# `media.incoming/<date>/`); here it is catalogued and cut.
#
#   media-index --incoming DIR --catalog DIR [--whisper-model FILE]
#       every clip under incoming/<date>/ becomes catalog/<id>.json, typed
#       as media.clips: duration, resolution, codec, frame rate (ffprobe),
#       scene cuts (ffmpeg, at media.sceneThreshold) and a transcript
#       (whisper.cpp, the model media.whisperModel pins by hash)
#   media-render CUTLIST.json --catalog DIR --incoming DIR --out FILE.mp4
#       applies a cut list ({ source; segments = [{ startMs; endMs; }];
#       targetMs; }) after checking it by the rule ./_lean/Clips.lean
#       states; the same cut list over the same source gives the same bytes
#
# The step that writes a cut list from a request ("a 30 s clip of
# yesterday's ride, fast cuts") is another team's; it only has to produce
# the typed JSON above. Every time is in whole milliseconds, in the
# catalog, the cut list, the Rust crate (./_src) and Lean, so all three
# decide the same numbers. checks.media-clips has Lean prove the rule's
# guarantees (a valid cut list never reads past a clip's end; its render is
# bounded by media.maxClipSeconds), decides the declared limits, and runs
# the crate's tests: the validator against the same cases as Lean, and an
# index-and-render round trip over a synthetic clip (ffmpeg's testsrc and
# sine). Transcription is not exercised in the check: the model is a
# 488 MB download, so it is fetched at build for the host alone
# (./_host.nix) and runs there. No secrets.
{ lib, config, ... }:
let
  inherit (lib) mkOption types;
  cfg = config.media;
  ms = s: s * 1000;

  line = types.submodule {
    options = {
      startMs = mkOption { type = types.ints.unsigned; };
      endMs = mkOption { type = types.ints.unsigned; };
      text = mkOption { type = types.str; };
    };
  };

  # One catalogued clip: catalog/<id>.json. Mirrored by `Clip` in
  # ./_src/src/lib.rs and ./_lean/Clips.lean.
  clip = types.submodule {
    options = {
      id = mkOption { type = types.strMatching "[a-z0-9][a-z0-9-]*"; };
      source = mkOption {
        type = types.str;
        description = "The file under media.incoming: <date>/<name>.";
      };
      date = mkOption { type = types.strMatching "[0-9]{4}-[0-9]{2}-[0-9]{2}"; };
      durationMs = mkOption { type = types.ints.unsigned; };
      width = mkOption { type = types.ints.unsigned; };
      height = mkOption { type = types.ints.unsigned; };
      codec = mkOption { type = types.str; };
      fps = mkOption { type = types.number; };
      hasAudio = mkOption { type = types.bool; };
      sceneThreshold = mkOption { type = types.numbers.between 0 1; };
      scenes = mkOption {
        type = types.listOf types.ints.unsigned;
        description = "Where the picture changes, milliseconds from the start, ascending.";
      };
      whisperModel = mkOption {
        type = types.nullOr types.str;
        description = "The model file the transcript came from; null when indexed without one.";
      };
      transcript = mkOption { type = types.listOf line; };
    };
  };

  # The declared limits, for Lean to decide after ./_lean/Clips.lean.
  rendered = ''
    namespace Kagamizo.Clips

    /-- media.maxClipSeconds, in milliseconds (rendered by modules/media/default.nix). -/
    def maxMs : Nat := ${toString (ms cfg.maxClipSeconds)}

    /-- media.toleranceMs. -/
    def toleranceMs : Nat := ${toString cfg.toleranceMs}

    theorem tolerance_below_max : toleranceMs < maxMs := by decide

    /-- With the declared limits, every valid cut list renders within media.maxClipSeconds. -/
    theorem length_bounded_declared {d : Nat} {c : CutList}
        (h : valid d toleranceMs maxMs c = true) : c.total ≤ maxMs :=
      length_bounded h

    /-- A clip of exactly the longest length is accepted; one millisecond more is refused. -/
    example : valid maxMs toleranceMs maxMs ⟨"c", [⟨0, maxMs⟩], maxMs⟩ = true := by decide
    example : valid (maxMs + 1) toleranceMs maxMs ⟨"c", [⟨0, maxMs + 1⟩], maxMs + 1⟩ = false := by
      decide

    end Kagamizo.Clips
  '';
in
{
  options.media = {
    sceneThreshold = mkOption {
      type = types.numbers.between 0 1;
      default = 0.4;
      description = "ffmpeg's scene-change score above which the indexer records a cut.";
    };
    whisperModel = mkOption {
      type = types.submodule {
        options = {
          repo = mkOption { type = types.strMatching "[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+"; };
          file = mkOption { type = types.strMatching "ggml-[a-z0-9.-]+\\.bin"; };
          sha256 = mkOption { type = types.strMatching "[0-9a-f]{64}"; };
        };
      };
      description = "The whisper.cpp model, pinned by hash and fetched at build (./_host.nix).";
    };
    maxClipSeconds = mkOption {
      type = types.ints.positive;
      default = 120;
      description = "The longest clip a cut list may ask for.";
    };
    toleranceMs = mkOption {
      type = types.ints.unsigned;
      default = 500;
      description = "How far the segments' total may be from the target.";
    };
    incoming = mkOption {
      type = types.str;
      default = "/var/lib/media/incoming";
      description = "Where footage arrives: <date>/<file>.";
    };
    catalog = mkOption {
      type = types.str;
      default = "/var/lib/media/catalog";
      description = "Where the indexer writes <id>.json.";
    };
    cuts = mkOption {
      type = types.str;
      default = "/var/lib/media/cuts";
      description = "Where cut lists are placed: media-render@<name> renders <name>.json.";
    };
    renders = mkOption {
      type = types.str;
      default = "/var/lib/media/renders";
      description = "Where media-render@ writes <name>.mp4.";
    };
    clips = mkOption {
      type = types.attrsOf clip;
      default = { };
      description = "The catalog's schema, as options; a clip declared here is type-checked at evaluation.";
    };
  };

  config = {
    media = {
      # The owner's choice (2026-11-04): whisper small. English only, as the
      # camera's audio is; hashes from huggingface.co/api/models/ggerganov/whisper.cpp/tree/main.
      whisperModel = {
        repo = "ggerganov/whisper.cpp";
        file = "ggml-small.en.bin";
        sha256 = "c6138d6d58ecc8322097e0f987c32f1be8bb0a18532a3f88f734d1bbf9c41e5d";
      };
      # The crate's fixture, typed here: the schema has one source.
      clips.example = builtins.fromJSON (builtins.readFile ./_src/fixtures/example-clip.json);
    };

    perSystem =
      { pkgs, ... }:
      let
        crate = pkgs.rustPlatform.buildRustPackage {
          pname = "media";
          version = "0.1.0";
          src = ./_src;
          cargoLock.lockFile = ./_src/Cargo.lock;
          # The pinned tools and the declared limits, baked in.
          FFMPEG = lib.getExe' pkgs.ffmpeg "ffmpeg";
          FFPROBE = lib.getExe' pkgs.ffmpeg "ffprobe";
          WHISPER_CLI = lib.getExe' pkgs.whisper-cpp "whisper-cli";
          MEDIA_MAX_MS = toString (ms cfg.maxClipSeconds);
          MEDIA_TOLERANCE_MS = toString cfg.toleranceMs;
          MEDIA_SCENE_THRESHOLD = toString cfg.sceneThreshold;
          # The tests are checks.media-clips.
          doCheck = false;
        };
        bin =
          name:
          pkgs.runCommand name { meta.mainProgram = name; } ''
            mkdir -p $out/bin
            ln -s ${crate}/bin/${name} $out/bin/${name}
          '';
      in
      {
        packages = {
          media-index = bin "media-index";
          media-render = bin "media-render";
        };

        checks.media-clips =
          pkgs.runCommand "media-clips"
            {
              nativeBuildInputs = [ pkgs.lean4 ];
              facts = rendered;
              passAsFile = [ "facts" ];
              tested = crate.overrideAttrs (_: {
                doCheck = true;
              });
            }
            ''
              cat ${./_lean/Clips.lean} "$factsPath" > Check.lean
              lean Check.lean
              echo "crate tests passed in $tested"
              touch $out
            '';
      };
  };
}
