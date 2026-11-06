# The trading module's Rust (./_rust, one Cargo workspace), replacing its
# Python as the language rule requires:
#   kagamizo-weather   the weather rules: probability and edge, ported from
#                      ./_weather.py with its tests on ./_json/forecasts.json
#   weather-backtest   the replay of those rules over settled days, within
#                      the strategy's declared limits (sample days in
#                      ./_json/backtest-days.json)
#   nautilus-probe     NautilusTrader's Rust engine with no Python: a
#                      simulated venue, SPY quotes and the EMA-cross
#                      example, run to fills (./_json/nautilus-rust-api.json
#                      maps the crates; LGPL-3.0, linked, not copied)
#
#   packages.weather-backtest   the binaries; the tests run as they build
#   checks.weather-backtest     the same build: every crate's tests pass
#                               (Nautilus excluded: it builds on its own)
#   packages.nautilus-probe     the probe
#   checks.nautilus-probe       the probe as its own builder: $out exists
#                               only when every order filled
{ lib, inputs, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      crate = pkgs.rustPlatform.buildRustPackage {
        pname = "weather-backtest";
        version = "0.1.0";
        src = ./_rust;
        cargoLock.lockFile = ./_rust/Cargo.lock;
        doCheck = true;
        cargoBuildFlags = [
          "--workspace"
          "--exclude"
          "nautilus-probe"
        ];
        cargoTestFlags = [
          "--workspace"
          "--exclude"
          "nautilus-probe"
        ];
        # The rule tests read the strategy's own fixture; the replay's tests
        # read the sample days.
        FIXTURE_PATH = ./_json/forecasts.json;
        DAYS_PATH = ./_json/backtest-days.json;
        meta.mainProgram = "weather-backtest";
      };
      # NautilusTrader 0.67 needs rustc 1.99.1; nixpkgs has 1.95.
      rust = (pkgs.extend inputs.rust-overlay.overlays.default).rust-bin.stable."1.99.1".minimal;
      rustPlatform = pkgs.makeRustPlatform {
        cargo = rust;
        rustc = rust;
      };
      probe = rustPlatform.buildRustPackage {
        pname = "nautilus-probe";
        version = "0.1.0";
        src = ./_rust;
        cargoLock.lockFile = ./_rust/Cargo.lock;
        cargoBuildFlags = [
          "-p"
          "nautilus-probe"
        ];
        doCheck = false;
        meta.mainProgram = "nautilus-probe";
      };
    in
    {
      packages.weather-backtest = crate;
      checks.weather-backtest = crate;
      packages.nautilus-probe = probe;
      checks.nautilus-probe = derivation {
        name = "nautilus-probe-run";
        inherit (pkgs.stdenv.hostPlatform) system;
        builder = lib.getExe probe;
      };
    };
}
