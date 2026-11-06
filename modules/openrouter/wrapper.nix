# `nix run .#openrouter -- <plan|apply|models|credits|usage|probe>`: the
# OpenRouter account as code, in Rust (./_spend/src/openrouter.rs). Every
# setting of the account is declared here or in ./openrouter.nix and
# rendered into one file the tool is built with:
#
#   openrouter.keys.<n>          ours: minted as kagamizo/<n> (./openrouter.nix)
#   openrouter.adoptedKeys.<n>   keys OpenRouter made, declared by their name
#                                and held to a decision (disabled, cap)
#   openrouter.guardrails        one per routing class (./routing.nix): the
#                                models and providers its keys may reach
#   openrouter.workspace         the workspace's defaults: its provider sort
#                                and default model
#
# `plan` fails on any drift and on anything live that is not declared, so
# no key, guardrail or workspace is ever left implicit.
{
  lib,
  config,
  ...
}:
let
  inherit (lib) mkOption types;
  top = config;
  cfg = config.openrouter;
  adopted = types.submodule {
    options = {
      label = mkOption {
        type = types.str;
        description = "Its name at OpenRouter.";
      };
      limitUsd = mkOption {
        type = types.nullOr types.ints.positive;
        description = "Its cap, as decided (null: none).";
      };
      reset = mkOption {
        type = types.nullOr (
          types.enum [
            "daily"
            "weekly"
            "monthly"
          ]
        );
        default = null;
      };
      disabled = mkOption {
        type = types.bool;
        description = "Whether it is turned off.";
      };
      why = mkOption { type = types.str; };
    };
  };
in
{
  options.openrouter = {
    adoptedKeys = mkOption {
      type = types.attrsOf adopted;
      default = { };
      description = "Keys OpenRouter made (not minted by us), each declared with its decision.";
    };
    workspace = {
      slug = mkOption {
        type = types.str;
        default = "default";
      };
      defaultProviderSort = mkOption {
        type = types.nullOr (
          types.enum [
            "price"
            "throughput"
            "latency"
            "exacto"
          ]
        );
        description = "How OpenRouter orders a request's allowed providers.";
      };
      defaultTextModel = mkOption { type = types.nullOr types.str; };
    };
  };

  config = {
    openrouter = {
      # Made by OpenRouter at signup (2026-11-02): $100, no reset, expires
      # 2027-05-02, never used. Nothing of ours holds it; off until a
      # declaration needs it.
      adoptedKeys.signup-default = {
        label = "Default key";
        limitUsd = 100;
        disabled = true;
        why = "OpenRouter's signup key, unused: disabled, so every live key is one we declared a use for";
      };
      # Cheapest first among the providers a key's guardrail allows.
      workspace = {
        defaultProviderSort = "price";
        defaultTextModel = cfg.defaultModel;
      };
    };

    perSystem =
      { pkgs, config, ... }:
      let
        declared = pkgs.writeText "openrouter-declared.json" (
          builtins.seq top.accounts.checked (
            builtins.toJSON {
              secretspec = lib.getExe config.packages.secretspec;
              spec = "${config.packages.secretspec-toml}";
              keys =
                lib.mapAttrs (n: k: {
                  label = "kagamizo/${n}";
                  minted = true;
                  inherit (k)
                    profile
                    variable
                    reset
                    limitUsd
                    ;
                  disabled = false;
                }) cfg.keys
                // lib.mapAttrs (_: k: {
                  inherit (k)
                    label
                    reset
                    disabled
                    limitUsd
                    ;
                  minted = false;
                  profile = null;
                  variable = null;
                }) cfg.adoptedKeys;
              guardrails = lib.mapAttrs (n: c: {
                label = "kagamizo/${n}";
                description = "routing class ${n} (modules/openrouter/routing.nix): ${c.model} at ${lib.concatStringsSep ", " c.endpoints}";
                allowedModels = [ c.model ];
                allowedProviders = c.providers;
                inherit (c) keys;
              }) cfg.routing;
              inherit (cfg) workspace models;
            }
          )
        );
        tools = pkgs.rustPlatform.buildRustPackage {
          pname = "openrouter-tools";
          version = "0.1.0";
          src = ./_spend;
          cargoLock.lockFile = ./_spend/Cargo.lock;
          doCheck = true;
          OPENROUTER_DECLARED = declared;
          meta.mainProgram = "openrouter";
        };
      in
      {
        packages.openrouter-tools = tools;
        packages.openrouter = tools;
      };
  };
}
