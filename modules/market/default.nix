# The market: every resource we buy, priced across providers like an order
# book, so cost is compared the way latency is. Classes and what we have
# chosen are code (they bind spend); the rates are data the host refreshes
# (./_data/rates.json), dated and unverified until a live price confirms
# them, the way scout's candidates are.
#
#   market.classes.<c> = { unit; description; }
#   market.rates.<c> = [ { provider; usd; unit; source; verified; held; note } ]
#   market.chosen.<c> = { provider; reason; }   reason required off the cheapest
#   market.policy.premiumPct                    how far off the cheapest a
#                                               reasoned choice may sit
#
#   nix run .#market -- compare <class>   the order book, cheapest first
#   nix run .#market -- chosen            what we use, and the premium paid
#   nix run .#market -- gaps              classes single-sourced or unpicked
#
# checks.market-lean (./_lean/Market.lean) proves every chosen provider is a
# real rate of its class and sits within the capped premium of the cheapest
# (or is single-sourced, or has a reason within twice the cheapest). A class
# with one rate or none is a gap the CLI shows, not a failure: liquidity is
# a thing to watch, not a thing the types forbid.
{ lib, config, ... }:
let
  inherit (lib) mkOption types;
  cfg = config.market;
  q = builtins.toJSON;
  micros = usd: builtins.floor (usd * 1000000 + 0.5);

  rate = types.submodule {
    options = {
      provider = mkOption { type = types.strMatching "[A-Za-z0-9][A-Za-z0-9/.:_-]*"; };
      usd = mkOption { type = types.numbers.nonnegative; };
      unit = mkOption { type = types.str; };
      source = mkOption { type = types.strMatching "https://.+"; };
      verified = mkOption {
        type = types.nullOr (types.strMatching "[0-9]{4}-[0-9]{2}-[0-9]{2}");
        default = null;
      };
      held = mkOption {
        type = types.bool;
        default = false;
      };
      note = mkOption {
        type = types.str;
        default = "";
      };
    };
  };
  class = types.submodule {
    options = {
      unit = mkOption { type = types.str; };
      description = mkOption { type = types.str; };
    };
  };
  chosen = types.submodule {
    options = {
      provider = mkOption { type = types.str; };
      reason = mkOption {
        type = types.str;
        default = "";
      };
    };
  };

  providersOf = c: map (r: r.provider) cfg.rates.${c} or [ ];
  problems =
    lib.concatLists (
      lib.mapAttrsToList (
        c: ch:
        lib.optional (
          !(lib.elem ch.provider (providersOf c))
        ) "market.chosen.${c}: ${ch.provider} is not a declared rate of ${c}"
      ) cfg.chosen
    )
    ++ lib.concatLists (
      lib.mapAttrsToList (
        c: _: lib.optional (!(cfg.classes ? ${c})) "market.rates.${c}: no such class is declared"
      ) cfg.rates
    );

  lean = ''
    namespace Kagamizo.Market

    def rates : List Rate := [
    ${lib.concatStringsSep ",\n" (
      lib.concatLists (
        lib.mapAttrsToList (
          c: rs:
          map (r: "  { cls := ${q c}, provider := ${q r.provider}, micros := ${toString (micros r.usd)} }") rs
        ) cfg.rates
      )
    )}
    ]

    def chosen : List Chosen := [
    ${lib.concatStringsSep ",\n" (
      lib.mapAttrsToList (
        c: ch: "  { cls := ${q c}, provider := ${q ch.provider}, reason := ${q ch.reason} }"
      ) cfg.chosen
    )}
    ]

    theorem declared_sound : sound rates ${toString cfg.policy.premiumPct} chosen = true := by decide +kernel

    end Kagamizo.Market
  '';

  rendered = {
    inherit (cfg) classes rates chosen;
    inherit (cfg.policy) premiumPct;
  };
in
{
  options.market = {
    classes = mkOption {
      type = types.attrsOf class;
      default = { };
    };
    rates = mkOption {
      type = types.attrsOf (types.listOf rate);
      default = { };
    };
    chosen = mkOption {
      type = types.attrsOf chosen;
      default = { };
    };
    policy.premiumPct = mkOption {
      type = types.ints.between 0 100;
      default = 25;
      description = "How far above the cheapest a reasoned choice may sit.";
    };
  };

  config = {
    market = {
      classes = {
        tokens = {
          unit = "USD per 1M output tokens";
          description = "LLM inference: the agents' and units' model calls";
        };
        cpu = {
          unit = "USD per vCPU-month";
          description = "The always-on host and any compute we rent";
        };
        gpu = {
          unit = "USD per GPU-hour";
          description = "Image and video generation, and heavier inference";
        };
        storage = {
          unit = "USD per GB-month";
          description = "The build cache, backups, records";
        };
        egress = {
          unit = "USD per GB";
          description = "Data leaving a provider: often the hidden cost";
        };
        domains = {
          unit = "USD per .com-year";
          description = "Registrations and renewals";
        };
      };
      rates = lib.importJSON ./_data/rates.json;
      chosen = {
        # Within 25% of the batch rate, and interactive work cannot wait for
        # a batch window, so the reason stands.
        tokens = {
          provider = "openrouter/deepseek-v4-flash";
          reason = "interactive; the batch rate adds minutes of latency";
        };
        cpu.provider = "hetzner/cx33";
        storage.provider = "cloudflare/r2";
        egress.provider = "cloudflare/r2";
        domains.provider = "cloudflare/registrar";
      };
    };

    perSystem =
      { pkgs, ... }:
      let
        facts = pkgs.writeText "market-facts.rs" (q rendered);
        market = pkgs.rustPlatform.buildRustPackage {
          pname = "market";
          version = "0.1.0";
          src = ./_src;
          cargoLock.lockFile = ./_src/Cargo.lock;
          MARKET_FACTS = facts;
          meta.mainProgram = "market";
        };
      in
      {
        packages.market = market;
        checks = {
          market-lean =
            assert lib.assertMsg (problems == [ ]) (lib.concatStringsSep "\n" problems);
            pkgs.runCommand "market-lean"
              {
                nativeBuildInputs = [ pkgs.lean4 ];
                facts = lean;
                passAsFile = [ "facts" ];
              }
              ''
                cat ${./_lean/Market.lean} "$factsPath" > Check.lean
                lean Check.lean
                touch $out
              '';
          market-tests = market.overrideAttrs (_: {
            doCheck = true;
          });
          market-data = pkgs.runCommand "market-data" { nativeBuildInputs = [ pkgs.jq ]; } ''
            f=${./_data/rates.json}
            jq -S --indent 2 . "$f" | diff -u - "$f" || {
              echo "$f is not canonical: jq -S --indent 2" >&2
              exit 1
            }
            touch $out
          '';
        };
      };
  };
}
