# What the twin adopts instead of building (the owner's direction,
# 2026-11-06): Minecraft is the single visual layer, a Rust server holds the
# digital twin, and the status page is a map rendering of that server with
# its stats. Every part is an existing open-licensed project, pinned by
# commit with its licence read from the repository; REA (modules/rea) maps
# each one, and its own tests are ported into our checks before it is
# trusted.
#
#   twin.adoptions.<name> = { role; repo; rev; license; language; protocol;
#                             lastCommit; use; tests; why; }
#
# checks.twin-adoptions (./_lean/Adoptions.lean) decides: every pinned
# adoption has an open licence, and a copyleft one (GPL, AGPL) runs only as
# its own process; every pinned server, bot, map renderer and browser view
# is Rust; a study-only adoption is never pinned; and every pinned one has
# named the tests we port from it.
#
# Read on 2026-11-06 from each repository at the commit given.
{ lib, config, ... }:
let
  inherit (lib) mkOption types;
  cfg = config.twin.adoptions;

  adoption = types.submodule {
    options = {
      role = mkOption {
        type = types.enum [
          "server"
          "bot"
          "map-render"
          "browser-view"
          "map-format"
          "minimap"
          "web-map"
          "asset-pack"
        ];
      };
      repo = mkOption { type = types.strMatching "[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+"; };
      rev = mkOption { type = types.strMatching "[0-9a-f]{40}"; };
      license = mkOption {
        type = types.enum [
          "mit"
          "apache-2"
          "mit-or-apache-2"
          "bsd"
          "mpl-2"
          "cc0"
          "cc-by-4"
          "gpl-3"
          "agpl-3"
          "lgpl-3"
          "all-rights-reserved"
        ];
        description = "As read from the repository's licence file at rev.";
      };
      language = mkOption {
        type = types.enum [
          "rust"
          "java"
          "typescript"
          "assets"
        ];
      };
      protocol = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "The Minecraft version it speaks, where it speaks one.";
      };
      lastCommit = mkOption { type = types.strMatching "[0-9]{4}-[0-9]{2}-[0-9]{2}"; };
      use = mkOption {
        type = types.enum [
          "pin"
          "process"
          "study"
        ];
        description = "pin: built and linked; process: run unmodified as its own process; study: mapped with REA, never vendored.";
      };
      tests = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Its test suites we port into our checks (paths in its repository).";
      };
      why = mkOption { type = types.str; };
    };
  };

  q = builtins.toJSON;
  facts = ''

    namespace Kagamizo.Adoptions

    def adoptions : List Adoption := [
    ${lib.concatStringsSep ",\n" (
      lib.mapAttrsToList (
        n: a:
        "  { name := ${q n}, role := ${q a.role}, license := ${q a.license}, language := ${q a.language}, use := ${q a.use}, tests := ${toString (lib.length a.tests)} }"
      ) cfg
    )}
    ]

    theorem adoptions_sound : adoptions.all Adoption.sound = true := by decide +kernel

    end Kagamizo.Adoptions
  '';
in
{
  options.twin.adoptions = mkOption {
    type = types.attrsOf adoption;
    default = { };
    description = "Open projects the twin adopts, pinned or studied.";
  };

  config = {
    twin.adoptions = {
      pumpkin = {
        role = "server";
        repo = "Pumpkin-MC/Pumpkin";
        rev = "6361843f5d9029b0cf7ecd6b1f2e86ace1256934";
        license = "gpl-3";
        language = "rust";
        protocol = "26.3";
        lastCommit = "2026-11-05";
        use = "process";
        tests = [ "crates/pumpkin-world" ];
        why = "the active Rust server on the current protocol; GPL-3, so it runs as its own process and our plugins stay GPL-compatible";
      };
      azalea = {
        role = "bot";
        repo = "azalea-rs/azalea";
        rev = "0d38e0dcf47eb258c41b1b09ebc2bcde7253e185";
        license = "mit";
        language = "rust";
        protocol = "26.2";
        lastCommit = "2026-10-16";
        use = "pin";
        tests = [ "azalea-protocol" ];
        why = "Rust bots for the teams' characters in the world; its protocol must match the server's before they connect";
      };
      fastanvil = {
        role = "map-render";
        repo = "owengage/fastnbt";
        rev = "60c7ee0de70c7ce6bfffc553fe372f834c3b32e9";
        license = "mit";
        language = "rust";
        lastCommit = "2026-10-10";
        use = "pin";
        tests = [ "fastanvil" ];
        why = "renders the server's region files to map tiles: the status page's map is the real world";
      };
      bevy = {
        role = "browser-view";
        repo = "bevyengine/bevy";
        rev = "159fa8d8e5e11ba0d40f55e39986992520635f4f";
        license = "mit-or-apache-2";
        language = "rust";
        lastCommit = "2026-11-05";
        use = "pin";
        tests = [ "crates/bevy_sprite" ];
        why = "the map view in the browser, compiled to WebAssembly: zoom, pan and a minimap over the rendered tiles";
      };
      bevy-ecs-tilemap = {
        role = "browser-view";
        repo = "StarArawn/bevy_ecs_tilemap";
        rev = "9d9ec11818985672d4e626957213c05c70e2935a";
        license = "mit";
        language = "rust";
        lastCommit = "2026-10-21";
        use = "pin";
        tests = [ "examples" ];
        why = "draws the tile layers in Bevy";
      };
      rs-tiled = {
        role = "map-format";
        repo = "mapeditor/rs-tiled";
        rev = "1f9614905cc2c2337bfaa39ce6c24f0ba6bd5e2e";
        license = "mit";
        language = "rust";
        lastCommit = "2026-07-06";
        use = "pin";
        tests = [ "tests" ];
        why = "reads the Tiled overlay of districts, rooms and labels drawn over the world's map";
      };
      valence = {
        role = "server";
        repo = "valence-rs/valence";
        rev = "c4177cab47ae109c848a431756d5d7c0207c05ed";
        license = "mit";
        language = "rust";
        protocol = "1.20.1";
        lastCommit = "2026-06-15";
        use = "study";
        why = "MIT and ECS-based, but stalled on an old protocol; studied for its design, not run";
      };
      bluemap = {
        role = "web-map";
        repo = "BlueMap-Minecraft/BlueMap";
        rev = "96ae320d1d39581c10058d8222f2290f2fcb5333";
        license = "mit";
        language = "java";
        lastCommit = "2026-10-30";
        use = "study";
        why = "the reference web map: its tile layout, markers and live players, mapped with REA into our Rust renderer";
      };
      squaremap = {
        role = "web-map";
        repo = "jpenilla/squaremap";
        rev = "2e158c2f11b22923c29bdd91ed0dbab74d055d15";
        license = "mit";
        language = "java";
        lastCommit = "2026-10-21";
        use = "study";
        why = "a lighter top-down web map, studied for its render pipeline";
      };
      pl3xmap = {
        role = "web-map";
        repo = "granny/Pl3xMap";
        rev = "9876e4b651b7f136823f150ae943f3b1b388e23b";
        license = "mit";
        language = "java";
        lastCommit = "2026-10-13";
        use = "study";
        why = "a top-down web map with layered markers, studied for its overlays";
      };
      journeymap = {
        role = "minimap";
        repo = "TeamJM/journeymap";
        rev = "72847c8a94e0061b384ebf2781d081b8f3565c46";
        license = "all-rights-reserved";
        language = "java";
        lastCommit = "2026-04-09";
        use = "study";
        why = "the best-known minimap; its source is closed (all rights reserved), so only its public behaviour is studied";
      };
    };

    perSystem =
      { config, ... }:
      {
        checks.twin-adoptions = config.kagamizo.leanCheck {
          name = "twin-adoptions";
          source = ./_lean/Adoptions.lean;
          inherit facts;
        };
      };
  };
}
