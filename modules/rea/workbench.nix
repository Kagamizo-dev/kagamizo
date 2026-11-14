# The reverse-engineering workbench: what may be taken apart, and the tools
# that do it, on the devices that carry them (../shell targets).
#
#   rea.subjects.<s>   a program, device or protocol to map into a typed
#                      catalog: whose it is, under what licence, and why.
#                      The type is the exclusion: a subject belongs to a
#                      declared entity, and its purposes are interoperability,
#                      porting, repair, security research or the catalog.
#                      There is no purpose for defeating DRM, anti-cheat or a
#                      licence check, nor any for a third party's service.
#   rea.workbench.<w>  a pinned tool and the targets whose images carry it
#   rea.workbenchModule <target>   those tools as a NixOS module
#
#   checks.rea-subjects  Lean (./_lean/Workbench.lean): every subject has a
#                        purpose; a device or service is the owner's own; a
#                        tool goes only on our own images
{ lib, config, ... }:
let
  inherit (lib) mkOption types;
  top = config;
  cfg = config.rea;
  q = builtins.toJSON;
  targets = lib.attrNames config.shell.targets;

  subject = types.submodule {
    options = {
      kind = mkOption {
        type = types.enum [
          "software"
          "device"
          "protocol"
          "service"
        ];
      };
      owner = mkOption {
        type = types.enum (lib.attrNames config.identity.entities);
        description = "The declared entity that owns it, or holds its licence.";
      };
      licence = mkOption {
        type = types.enum [
          "owned"
          "licensed"
          "open-source"
        ];
        description = "owned: the entity's own device or service; licensed: software it holds a licence to; open-source: under an open licence.";
      };
      purposes = mkOption {
        type = types.listOf (
          types.enum [
            "interoperability"
            "porting"
            "repair"
            "security-research"
            "catalog"
          ]
        );
      };
      why = mkOption { type = types.str; };
    };
  };

  tool = types.submodule {
    options = {
      package = mkOption {
        type = types.str;
        description = "The nixpkgs attribute.";
      };
      targets = mkOption { type = types.listOf (types.enum targets); };
      why = mkOption { type = types.str; };
    };
  };
in
{
  options.rea = {
    subjects = mkOption {
      type = types.attrsOf subject;
      default = { };
    };
    workbench = mkOption {
      type = types.attrsOf tool;
      default = { };
    };
    workbenchModule = mkOption {
      type = types.functionTo types.raw;
      readOnly = true;
      description = "A target's workbench tools as a NixOS module, for its image to import.";
      default =
        t:
        { pkgs, lib, ... }:
        {
          environment.systemPackages = map (w: pkgs.${w.package}) (
            lib.filter (w: lib.elem t w.targets) (lib.attrValues cfg.workbench)
          );
        };
    };
  };

  config = {
    rea = {
      # What the owner's devices and the pinned software may be mapped for.
      subjects = {
        pixel-9a = {
          kind = "device";
          owner = "mirazo";
          licence = "owned";
          purposes = [
            "interoperability"
            "repair"
            "security-research"
            "catalog"
          ];
          why = "the kit's screen: what it exposes over USB, Bluetooth and its radios, so the kit drives it";
        };
        rpi5 = {
          kind = "device";
          owner = "mirazo";
          licence = "owned";
          purposes = [
            "interoperability"
            "porting"
            "catalog"
          ];
          why = "the kit's machine: its firmware and peripherals, so software is ported onto it";
        };
        yoga-c940 = {
          kind = "device";
          owner = "mirazo";
          licence = "owned";
          purposes = [
            "interoperability"
            "repair"
            "catalog"
          ];
          why = "the desk machine: its firmware and hardware, so the image drives all of it";
        };
        nautilus-trader = {
          kind = "software";
          owner = "jingzo";
          licence = "open-source";
          purposes = [
            "porting"
            "catalog"
          ];
          why = "the trading engine's Rust crates, mapped into a typed catalog for the port (reverse-engineering/nautilus-rust)";
        };
        jingzo-host = {
          kind = "service";
          owner = "jingzo";
          licence = "owned";
          purposes = [ "security-research" ];
          why = "the server and every service behind Access: the security team's own surface";
        };
      };

      # The tools, on the Yoga (with a screen) and the Pi (headless, in the
      # pocket). The Pi takes the command-line ones.
      workbench = {
        ghidra = {
          package = "ghidra";
          targets = [ "yoga-c940" ];
          why = "decompiling and annotating binaries of any architecture";
        };
        cutter = {
          package = "cutter";
          targets = [ "yoga-c940" ];
          why = "rizin's graphical front end";
        };
        imhex = {
          package = "imhex";
          targets = [ "yoga-c940" ];
          why = "a hex editor with patterns for file formats and firmware";
        };
        rizin = {
          package = "rizin";
          targets = [
            "yoga-c940"
            "rpi5"
          ];
          why = "disassembly and analysis from the command line";
        };
        radare2 = {
          package = "radare2";
          targets = [
            "yoga-c940"
            "rpi5"
          ];
          why = "disassembly, debugging and patching from the command line";
        };
        binwalk = {
          package = "binwalk";
          targets = [
            "yoga-c940"
            "rpi5"
          ];
          why = "finding and extracting what firmware images hold";
        };
        frida = {
          package = "frida-tools";
          targets = [
            "yoga-c940"
            "rpi5"
          ];
          why = "instrumenting running programs, on the device or over USB to the phone";
        };
      };
    };

    perSystem =
      { config, ... }:
      {
        checks.rea-subjects = config.kagamizo.leanCheck {
          name = "rea-subjects";
          source = ./_lean/Workbench.lean;
          facts = ''

            namespace Kagamizo.Workbench
            def subjects : List Subject := [${
              lib.concatStringsSep ",\n  " (
                lib.mapAttrsToList (
                  n: s:
                  "{ name := ${q n}, kind := .${s.kind}, owner := ${q s.owner}, licence := .${
                    if s.licence == "open-source" then "openSource" else s.licence
                  }, purposes := ${toString (lib.length s.purposes)} }"
                ) cfg.subjects
              )
            }]
            def tools : List Tool := [${
              lib.concatStringsSep ", " (
                lib.mapAttrsToList (n: w: "{ name := ${q n}, targets := ${q w.targets} }") cfg.workbench
              )
            }]
            def images : List String := ${
              q (lib.attrNames (lib.filterAttrs (_: t: t.kind == "nixos") top.shell.targets))
            }

            theorem workbench_sound : sound subjects tools images = true := by decide +kernel
            end Kagamizo.Workbench
          '';
        };
      };
  };
}
