# The digital twin's representation options: every module, account, team and
# asset gets a building, item, block or character with a sprite, a place in
# the world, and typed recipes that declare its governance actions.
#
#   twin.representations.<name> = {
#     kind;     # building, item, block, character
#     of;       # what it represents: { module = ".."; } / { account = ".."; } /
#               #   { team = ".."; } / { asset = ".."; }
#     sprite;   # 16x16 pixel art over the declared palette
#     place;    # district enum
#     recipes;  # typed actions with inputs/outputs
#     status;   # declared, running, paused, gap
#   }
#
#   twin.palette.<char> = "#rrggbb"
#   twin.districts.<name> = { label; order; }
#   twin.saves.<name> = { revision; takenAt; statestore; ledger; }
#
# The world is declared here and rendered by ./world.nix; Lean proves its
# shape (./_lean/Types.lean + rendered facts).
{ lib, config, ... }:
let
  inherit (lib) mkOption types;
  agents = config.governance.agents;

  # A sprite row: exactly 16 characters from the palette (hex digits 0-9 a-f).
  # At type-definition time we only know the palette key charset.
  spriteRowType = types.strMatching "^[0-9a-f]{16}$";

  # A full sprite: exactly 16 rows.
  spriteType = types.nullOr (
    types.addCheck (types.listOf spriteRowType) (rows: builtins.length rows == 16)
  );

  flattenActions = lib.concatLists (
    lib.mapAttrsToList (
      provider: as: lib.mapAttrsToList (name: _: "${provider}:${name}") as
    ) config.governance.actions
  );

  # Every module that has perf targets, so a representation.of.module is typed
  # to an existing one.
  perfModules = lib.unique (map (t: t.module) (lib.attrValues config.perf.targets));
in
{
  options.twin = {
    palette = mkOption {
      type = types.attrsOf (types.strMatching "#[0-9a-fA-F]{6}");
      default = { };
      description = "The sprite palette: one ASCII character per colour, #rrggbb.";
    };
    districts = mkOption {
      type = types.attrsOf (
        types.submodule {
          options = {
            label = mkOption {
              type = types.str;
              description = "Human-readable district name.";
            };
            order = mkOption {
              type = types.ints.unsigned;
              description = "Render order (lower is earlier/left).";
            };
            color = mkOption {
              type = types.submodule {
                options = {
                  light = mkOption {
                    type = types.strMatching "#[0-9a-fA-F]{6}";
                    description = "Ground tint in light mode.";
                  };
                  dark = mkOption {
                    type = types.strMatching "#[0-9a-fA-F]{6}";
                    description = "Ground tint in dark mode.";
                  };
                };
              };
              description = "District ground-tint colours for light and dark mode.";
            };
          };
        }
      );
      default = { };
      description = "Named districts, typed by their existence.";
    };
    representations = mkOption {
      type = types.attrsOf (
        types.submodule (
          _:
          let
            # Lazy: resolve from config at check time, when districts are set.
            districtNames = lib.attrNames config.twin.districts;
          in
          {
            options = {
              kind = mkOption {
                type = types.enum [
                  "building"
                  "item"
                  "block"
                  "character"
                ];
                description = "What kind of sprite this is in the world.";
              };
              of = mkOption {
                type = types.submodule {
                  options = {
                    module = mkOption {
                      type = types.nullOr (types.enum perfModules);
                      default = null;
                      description = "A module name from the perf targets.";
                    };
                    account = mkOption {
                      type = types.nullOr types.str;
                      default = null;
                      description = "An account identifier (provider-entity).";
                    };
                    team = mkOption {
                      type = types.nullOr (types.enum (lib.attrNames agents));
                      default = null;
                      description = "An agent team name.";
                    };
                    asset = mkOption {
                      type = types.nullOr types.str;
                      default = null;
                      description = "An asset identifier (key or card name).";
                    };
                  };
                };
                description = "What this representation stands for: exactly one of module, account, team, or asset must be non-null.";
              };
              sprite = mkOption {
                type = spriteType;
                default = null;
                description = "Exactly 16 palette-character rows of exactly 16 characters each. Null means the renderer uses a default sprite.";
              };
              place = mkOption {
                type = types.enum districtNames;
                description = "Which district this representation lives in.";
              };
              recipes = mkOption {
                type = types.listOf (
                  types.submodule {
                    options = {
                      action = mkOption {
                        type = types.enum flattenActions;
                        description = "The governance action this recipe wraps, as provider:name.";
                      };
                      inputs = mkOption {
                        type = types.listOf types.str;
                        default = [ ];
                        description = "Input names this recipe consumes.";
                      };
                      outputs = mkOption {
                        type = types.listOf types.str;
                        default = [ ];
                        description = "Output names this recipe produces.";
                      };
                    };
                  }
                );
                default = [ ];
                description = "The typed actions this representation exposes, as JEI-style recipes.";
              };
              status = mkOption {
                type = types.enum [
                  "declared"
                  "running"
                  "paused"
                  "gap"
                ];
                default = "declared";
                description = "Operational status of what this represents.";
              };
            };
          }
        )
      );
      default = { };
      description = "Every represented thing in the digital twin world.";
    };
    saves = mkOption {
      type = types.attrsOf (
        types.submodule {
          options = {
            revision = mkOption {
              type = types.str;
              description = "Git revision this save was taken at.";
            };
            takenAt = mkOption {
              type = types.str;
              description = "ISO-8601 timestamp of the save.";
            };
            statestore = mkOption {
              type = types.str;
              description = "Hash or reference into the statestore.";
            };
            ledger = mkOption {
              type = types.str;
              description = "Hash or reference of the ledger at save time.";
            };
          };
        }
      );
      default = { };
      description = "Named world saves: a revision, timestamp, statestore and ledger ref. Not yet declared.";
    };
  };

  config.twin = {
    palette = {
      "0" = "#1d1c1a"; # ink
      "1" = "#fbfaf8"; # paper
      "2" = "#2b5fa8"; # accent blue
      "3" = "#b4441f"; # gap/red
      "4" = "#2f6f4f"; # ok green
      "5" = "#e4e1db"; # line
      "6" = "#6b6862"; # muted
      "7" = "#8db4ee"; # light blue
      "8" = "#ef8a64"; # soft red
      "9" = "#7fc4a0"; # soft green
      "a" = "#a3a09a"; # muted light
      "b" = "#34322f"; # dark line
      "c" = "#1e1e1c"; # card dark
      "d" = "#ecebe8"; # fg light
      "e" = "#151514"; # bg dark
      "f" = "#f0c040"; # gold
    };
    districts = {
      trading = {
        label = "Trading";
        order = 1;
        color = {
          light = "#d4e8d4";
          dark = "#1e3a1e";
        };
      };
      money = {
        label = "Money";
        order = 2;
        color = {
          light = "#e8d4c4";
          dark = "#3a2a1e";
        };
      };
      legal = {
        label = "Legal";
        order = 3;
        color = {
          light = "#d0d8ee";
          dark = "#1e2a4a";
        };
      };
      compliance = {
        label = "Compliance";
        order = 4;
        color = {
          light = "#e8d0e8";
          dark = "#3a1e3a";
        };
      };
      research = {
        label = "Research";
        order = 5;
        color = {
          light = "#d0eee8";
          dark = "#1e3a34";
        };
      };
      agents = {
        label = "Agents";
        order = 6;
        color = {
          light = "#e8e0c4";
          dark = "#3a341e";
        };
      };
      infra = {
        label = "Infrastructure";
        order = 7;
        color = {
          light = "#d0d0d0";
          dark = "#2a2a2a";
        };
      };
      media = {
        label = "Media";
        order = 8;
        color = {
          light = "#f0d4d4";
          dark = "#4a2a2a";
        };
      };
      home = {
        label = "Home";
        order = 9;
        color = {
          light = "#d4e8e0";
          dark = "#1e342e";
        };
      };
    };
  };

}
