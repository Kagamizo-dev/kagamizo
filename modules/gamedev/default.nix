# The game-development profile (the owner's decision, 2026-11-04): the
# Minecraft digital twin's mod work and custom game environments later;
# today the profile itself, declared and checked. Open source first: Godot
# and Blender (nixpkgs), the Java and Gradle toolchain the Fabric mod needs,
# Rust for the mod's core (the repo's convention). Steam is the one
# testing-and-shipping platform, unfree in nixpkgs, and it is off until the
# owner enables it on the host (gamedev.steam.enable).
#
#   gamedev.engines.<name>          an engine: its package, with the version
#                                   and licence nixpkgs states (read-only)
#   gamedev.toolchains.<name>       jdk, gradle, rust, cargo: the same shape
#   gamedev.steam.tools.<name>      steam, steamcmd, steam-run: the same
#                                   shape, admitted by name from a nixpkgs
#                                   of their own (as the Android SDK is)
#   gamedev.steam.enable            false. True puts Steam's tools in the
#                                   shell, admits their unfree names on the
#                                   host and installs steamcmd there
#   gamedev.unfreeNames             the names the host admits: Steam's when
#                                   enabled, none otherwise
#
#   nix develop .#gamedev           the shell: every engine and toolchain
#                                   (packages.gamedev-shell is the same)
#   nix run .#gamedev-versions      every pinned version, as JSON
#
# checks.gamedev-profile has Lean (./_lean/Profile.lean) decide, over the
# rendered profile, that every engine and toolchain is open source, that
# the only proprietary entries are the ones under gamedev.steam, and prove
# that enabling Steam adds exactly the Steam entries and nothing else; then
# it runs gamedev-versions and reads the JSON back.
{
  lib,
  config,
  inputs,
  ...
}:
let
  inherit (lib) mkOption types;
  cfg = config.gamedev;
  q = builtins.toJSON;

  # Steam's packages and their names, unfree in nixpkgs: the client, the
  # command line (for uploads and dedicated servers) and the FHS runner
  # both sit in (steam-run is MIT itself; what it runs is not).
  steamNames = [
    "steam"
    "steam-unwrapped"
    "steamcmd"
  ];

  # The first licence nixpkgs states for a package: its SPDX id, or its
  # short name when it has none (Steam's "unfreeRedistributable").
  licenseOf =
    p:
    let
      l = lib.head (lib.toList (p.meta.license or (throw "gamedev: ${lib.getName p} states no licence")));
    in
    {
      id = l.spdxId or l.shortName;
      free = l.free or false;
    };

  # An engine, toolchain or platform tool: a package, read for its version
  # and licence.
  tool = types.submodule (
    { config, ... }:
    {
      options = {
        package = mkOption { type = types.package; };
        version = mkOption {
          type = types.str;
          readOnly = true;
          description = "From the package.";
        };
        license = mkOption {
          type = types.str;
          readOnly = true;
          description = "The SPDX id nixpkgs states, or its short name where there is none.";
        };
        proprietary = mkOption {
          type = types.bool;
          readOnly = true;
          description = "nixpkgs' verdict: not meta.license.free.";
        };
      };
      config = {
        version = config.package.version;
        license = (licenseOf config.package).id;
        proprietary = !(licenseOf config.package).free;
      };
    }
  );

  # The profile, as Lean sees it (./_lean/Profile.lean), after this module's
  # perSystem has read every package.
  rendered =
    g:
    let
      entry =
        platform: n: t:
        "{ name := ${q n}, license := ${q t.license}, proprietary := ${q t.proprietary}, platform := ${q platform} }";
      list = platform: set: lib.concatStringsSep ",\n  " (lib.mapAttrsToList (entry platform) set);
    in
    ''
      namespace Kagamizo.GameDev

      /-- Every engine and toolchain, rendered by modules/gamedev/default.nix. -/
      def base : List Tool := [
        ${list false (g.engines // g.toolchains)}
      ]

      /-- The platform's tools, under gamedev.steam. -/
      def steam : List Tool := [
        ${list true g.steam.tools}
      ]

      /-- gamedev.steam.enable, as declared. -/
      def enabled : Bool := ${q cfg.steam.enable}

      /-- Every engine and toolchain is open source. -/
      theorem base_open : base.all Tool.openSource = true := by decide +kernel

      /-- Every entry under gamedev.steam is marked as the platform's. -/
      theorem steam_platform : steam.all (·.platform) = true := by decide +kernel

      /-- The only proprietary entries of the profile, as declared, are the
      platform's. -/
      theorem declared_allowed : (profile base steam enabled).all Tool.allowed = true := by
        decide +kernel

      /-- And so for either setting of the switch: proprietary only under the
      platform. -/
      theorem rule_holds (e : Bool) :
          ∀ t ∈ profile base steam e, t.proprietary = true → t.platform = true :=
        rule base steam e base_open steam_platform

      /-- Enabling Steam adds exactly the Steam entries. -/
      theorem enabling_adds_steam : profile base steam true = base ++ steam :=
        profile_enabled base steam

      theorem disabling_leaves_base : profile base steam false = base :=
        profile_disabled base steam

      end Kagamizo.GameDev
    '';
in
{
  options = {
    gamedev = {
      steam.enable = mkOption {
        type = types.bool;
        default = false;
        description = "Steam's tools in the shell and on the host; the owner's switch.";
      };
      unfreeNames = mkOption {
        type = types.listOf types.str;
        readOnly = true;
        description = "The unfree names the host admits (../hetzner/_agents.nix, alsoUnfree).";
      };
    };

    perSystem = inputs.flake-parts.lib.mkPerSystemOption {
      options.gamedev = {
        engines = mkOption {
          type = types.attrsOf tool;
          description = "The engines: godot, blender.";
        };
        toolchains = mkOption {
          type = types.attrsOf tool;
          description = "The toolchains: jdk, gradle, rust, cargo.";
        };
        steam.tools = mkOption {
          type = types.attrsOf tool;
          description = "The platform's tools: steam, steamcmd, steam-run.";
        };
      };
    };
  };

  config = {
    gamedev.unfreeNames = lib.optionals cfg.steam.enable steamNames;

    perSystem =
      {
        config,
        pkgs,
        system,
        ...
      }:
      let
        g = config.gamedev;
        # Steam's packages are unfree: a nixpkgs of its own, admitting them
        # by name and nothing else (as ../android does for the SDK).
        spkgs = import inputs.nixpkgs {
          inherit system;
          config.allowUnfreePredicate = p: lib.elem (lib.getName p) steamNames;
        };
        packagesOf = set: map (t: t.package) (lib.attrValues set);
        versions = {
          engines = lib.mapAttrs (_: t: { inherit (t) version license; }) g.engines;
          toolchains = lib.mapAttrs (_: t: { inherit (t) version license; }) g.toolchains;
          steam = {
            inherit (cfg.steam) enable;
            tools = lib.mapAttrs (_: t: { inherit (t) version license; }) g.steam.tools;
          };
        };
        versionsJson = pkgs.writeText "gamedev-versions.json" (q versions);
      in
      {
        gamedev = {
          engines = {
            godot.package = pkgs.godot_4;
            blender.package = pkgs.blender;
          };
          toolchains = {
            jdk.package = pkgs.jdk21;
            gradle.package = pkgs.gradle;
            rust.package = pkgs.rustc;
            cargo.package = pkgs.cargo;
          };
          steam.tools = {
            steam.package = spkgs.steam;
            steamcmd.package = spkgs.steamcmd;
            steam-run.package = spkgs.steam-run;
          };
        };

        packages = {
          gamedev-shell = pkgs.mkShell {
            name = "gamedev";
            packages =
              packagesOf g.engines
              ++ packagesOf g.toolchains
              ++ [
                pkgs.rustfmt
                pkgs.clippy
              ]
              ++ lib.optionals cfg.steam.enable (packagesOf g.steam.tools);
            JAVA_HOME = g.toolchains.jdk.package.home or g.toolchains.jdk.package;
            shellHook = ''
              echo "gamedev: godot ${g.engines.godot.version}, blender ${g.engines.blender.version}, jdk ${g.toolchains.jdk.version}, gradle ${g.toolchains.gradle.version}, rust ${g.toolchains.rust.version}${lib.optionalString cfg.steam.enable ", steamcmd ${g.steam.tools.steamcmd.version}"}"
            '';
          };

          gamedev-versions = pkgs.writeShellApplication {
            name = "gamedev-versions";
            runtimeInputs = [ pkgs.coreutils ];
            text = ''
              cat ${versionsJson}
            '';
          };
        };

        devShells.gamedev = config.packages.gamedev-shell;

        checks.gamedev-profile =
          pkgs.runCommand "gamedev-profile"
            {
              nativeBuildInputs = [
                pkgs.lean4
                pkgs.jq
                config.packages.gamedev-versions
              ];
              facts = rendered g;
              passAsFile = [ "facts" ];
            }
            ''
              cat ${./_lean/Profile.lean} "$factsPath" > Check.lean
              lean Check.lean

              # The versions the shell pins, as the wrapper prints them: every
              # engine and toolchain named, each with a version and a licence.
              gamedev-versions > versions.json
              for want in engines.godot engines.blender toolchains.jdk toolchains.gradle toolchains.rust \
                          steam.tools.steamcmd; do
                jq -e ".$want.version != \"\" and .$want.license != \"\"" versions.json >/dev/null \
                  || { echo "gamedev-profile: $want has no version or licence" >&2; exit 1; }
              done
              jq -e '.steam.enable == ${q cfg.steam.enable}' versions.json >/dev/null
              touch $out
            '';
      };
  };
}
