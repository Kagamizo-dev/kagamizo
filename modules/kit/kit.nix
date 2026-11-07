# The carried kit: a solo researcher's whole stack, worn in the pockets and
# sleeves of their clothes (the owner's goal, 2026-11-07). The phone is the
# screen, the Raspberry Pi the machine; every item that runs software is a
# target of the shell (../shell), so the same shell runs on all of them.
#
#   kit.slots.<s>       a place on the clothing, with its volume and mass
#   kit.items.<i>       a device: its slot, mass, volume, draw, battery,
#                       whether it runs on the shared bank, what it provides,
#                       and whether it is owned or a proposal
#   kit.required.now    what the owned items must carry, and for how long
#   kit.required.target what the owned items and the proposals must carry
#
# A proposal is a specification, not a product: at most its mass, volume
# and draw, at least its battery. A purchase is the owner's decision; no
# agent buys anything here.
#
#   checks.kit          Lean (./_lean/Kit.lean): every slot holds what is in
#                       it, the requirements are covered, every item lasts
#                       the hours on its battery or the bank, and every item
#                       that runs software is a shell target
{ lib, config, ... }:
let
  inherit (lib) mkOption types;
  cfg = config.kit;
  targets = lib.attrNames config.shell.targets;
  q = builtins.toJSON;

  capabilities = [
    "compute-x86"
    "compute-arm"
    "display"
    "touch"
    "keyboard"
    "pointer"
    "gamepad"
    "network-cellular"
    "network-wifi"
    "network-wifi-monitor"
    "radio-sdr"
    "radio-nfc-rfid"
    "radio-subghz"
    "storage"
    "power"
    "camera"
    "gps"
  ];

  slot = types.submodule {
    options = {
      volumeMl = mkOption { type = types.ints.positive; };
      massG = mkOption { type = types.ints.positive; };
    };
  };

  item = types.submodule {
    options = {
      device = mkOption {
        type = types.str;
        description = "What it is: the product if owned, the specification if a proposal.";
      };
      slot = mkOption { type = types.enum (lib.attrNames cfg.slots); };
      massG = mkOption { type = types.ints.unsigned; };
      volumeMl = mkOption { type = types.ints.unsigned; };
      powerMw = mkOption {
        type = types.ints.unsigned;
        description = "Its average draw in the field, in milliwatts.";
      };
      batteryMwh = mkOption {
        type = types.ints.unsigned;
        default = 0;
      };
      bank = mkOption {
        type = types.bool;
        default = false;
        description = "Whether it draws from the kit's shared bank rather than its own battery.";
      };
      provides = mkOption { type = types.listOf (types.enum capabilities); };
      owned = mkOption { type = types.bool; };
      runsSoftware = mkOption {
        type = types.bool;
        default = false;
      };
      source = mkOption {
        type = types.str;
        description = "Where its figures come from: the maker's specification, or why the limit is what it is.";
      };
    };
  };

  requirement = types.submodule {
    options = {
      capabilities = mkOption { type = types.listOf (types.enum capabilities); };
      hours = mkOption { type = types.ints.positive; };
    };
  };
in
{
  options.kit = {
    slots = mkOption { type = types.attrsOf slot; };
    items = mkOption { type = types.attrsOf item; };
    required = {
      now = mkOption { type = requirement; };
      target = mkOption { type = requirement; };
    };
  };

  config = {
    # The clothing's places, each with what it holds comfortably: a phone
    # fits a trouser pocket, a sleeve pocket takes a dongle, a jacket's inner
    # pocket takes a power bank.
    kit = {
      slots = {
        trouser-pocket-left = {
          volumeMl = 400;
          massG = 500;
        };
        trouser-pocket-right = {
          volumeMl = 400;
          massG = 500;
        };
        chest-pocket = {
          volumeMl = 250;
          massG = 300;
        };
        inner-pocket-left = {
          volumeMl = 600;
          massG = 700;
        };
        inner-pocket-right = {
          volumeMl = 600;
          massG = 700;
        };
        sleeve-left = {
          volumeMl = 120;
          massG = 150;
        };
        sleeve-right = {
          volumeMl = 120;
          massG = 150;
        };
        belt = {
          volumeMl = 500;
          massG = 600;
        };
        face = {
          volumeMl = 80;
          massG = 120;
        };
      };

      items = {
        # Owned.
        pixel-9a = {
          device = "Google Pixel 9a, GrapheneOS";
          slot = "trouser-pocket-left";
          massG = 186;
          volumeMl = 101;
          powerMw = 1200;
          batteryMwh = 19600;
          provides = [
            "display"
            "touch"
            "network-cellular"
            "network-wifi"
            "camera"
            "gps"
            "storage"
          ];
          owned = true;
          runsSoftware = true;
          source = "Google's specification: 154.7 x 73.3 x 8.9 mm, 186 g, 5100 mAh at 3.85 V; draw is a mixed screen-on day";
        };
        rpi5 = {
          device = "Raspberry Pi 5 in a case";
          slot = "trouser-pocket-right";
          massG = 110;
          volumeMl = 180;
          powerMw = 5000;
          bank = true;
          provides = [
            "compute-arm"
            "storage"
            "network-wifi"
          ];
          owned = true;
          runsSoftware = true;
          source = "Raspberry Pi's product brief: 85 x 56 mm board, 2.7 W idle; 5 W is the field budget for the shell, a small model and the tools, in a case with its cooler";
        };

        # Proposals: what a product must meet to join the kit.
        power-bank = {
          device = "USB-C PD power bank, 45 W out, at least 99 Wh (about 26800 mAh)";
          slot = "inner-pocket-left";
          massG = 550;
          volumeMl = 350;
          powerMw = 0;
          batteryMwh = 99000;
          provides = [ "power" ];
          owned = false;
          source = "The bank powers the Pi and the glasses for a day (9.5 W for 8 hours is 76 Wh); 99 Wh is the most airlines allow in a cabin without approval";
        };
        display-glasses = {
          device = "Display glasses over USB-C (DisplayPort alternate mode)";
          slot = "face";
          massG = 90;
          volumeMl = 80;
          powerMw = 1500;
          bank = true;
          provides = [ "display" ];
          owned = false;
          source = "A private screen for the Pi when the phone is put away; the limit is a pair of sunglasses";
        };
        keyboard = {
          device = "Folding Bluetooth keyboard with a touchpad";
          slot = "inner-pocket-right";
          massG = 200;
          volumeMl = 200;
          powerMw = 100;
          batteryMwh = 1500;
          provides = [
            "keyboard"
            "pointer"
          ];
          owned = false;
          source = "Typing code in the field; its own battery lasts the day at this draw";
        };
        gamepad = {
          device = "Clip-on Bluetooth gamepad";
          slot = "belt";
          massG = 200;
          volumeMl = 250;
          powerMw = 200;
          batteryMwh = 2000;
          provides = [ "gamepad" ];
          owned = false;
          source = "The shell's console-style input, and play";
        };
        sdr = {
          device = "USB software-defined radio receiver";
          slot = "sleeve-right";
          massG = 100;
          volumeMl = 100;
          powerMw = 1500;
          bank = true;
          provides = [ "radio-sdr" ];
          owned = false;
          source = "Receiving and analysing radio for the security and reverse-engineering work on the owner's own devices";
        };
        nfc-tool = {
          device = "Handheld NFC, RFID and sub-GHz research tool";
          slot = "sleeve-left";
          massG = 110;
          volumeMl = 110;
          powerMw = 300;
          batteryMwh = 7000;
          provides = [
            "radio-nfc-rfid"
            "radio-subghz"
          ];
          owned = false;
          source = "Reading and testing the owner's own cards, tags and devices";
        };
        wifi-adapter = {
          device = "USB Wi-Fi adapter with monitor mode";
          slot = "belt";
          massG = 40;
          volumeMl = 40;
          powerMw = 1500;
          bank = true;
          provides = [ "network-wifi-monitor" ];
          owned = false;
          source = "Testing the owner's own wireless networks from the Pi";
        };
      };

      # Today the phone carries itself for a day; the Pi runs on the bank, so
      # until a bank is owned it stays home, and the target needs the bank.
      required = {
        now = {
          capabilities = [
            "display"
            "touch"
            "network-cellular"
            "camera"
            "gps"
            "storage"
          ];
          hours = 8;
        };
        target = {
          # Everything but x86: the Yoga stays at the desk, and the Pi runs
          # x86 programs through a translator (../shell runtimes).
          capabilities = lib.remove "compute-x86" capabilities;
          hours = 8;
        };
      };
    };

    perSystem =
      { config, ... }:
      let
        render =
          n: i:
          "{ name := ${q n}, slot := ${q i.slot}, massG := ${toString i.massG}, volumeMl := ${toString i.volumeMl}, powerMw := ${toString i.powerMw}, batteryMwh := ${toString i.batteryMwh}, bank := ${lib.boolToString i.bank}, provides := ${q i.provides}, owned := ${lib.boolToString i.owned}, runsSoftware := ${lib.boolToString i.runsSoftware} }";
        req = r: "{ capabilities := ${q r.capabilities}, hours := ${toString r.hours} }";
      in
      {
        checks.kit = config.kagamizo.leanCheck {
          name = "kit";
          source = ./_lean/Kit.lean;
          facts = ''

            namespace Kagamizo.Kit
            def slots : List Slot := [${
              lib.concatStringsSep ", " (
                lib.mapAttrsToList (
                  n: s: "{ name := ${q n}, volumeMl := ${toString s.volumeMl}, massG := ${toString s.massG} }"
                ) cfg.slots
              )
            }]
            def items : List Item := [${lib.concatStringsSep ",\n  " (lib.mapAttrsToList render cfg.items)}]
            def targets : List String := ${q targets}
            def now : Requirement := ${req cfg.required.now}
            def target : Requirement := ${req cfg.required.target}

            theorem kit_sound : sound slots targets now target items = true := by decide +kernel
            end Kagamizo.Kit
          '';
        };
      };
  };
}
