# The trading module's Rust (./_rust, one Cargo workspace), replacing its
# Python as the language rule requires:
#   kagamizo-weather   the weather rules: probability and edge, ported from
#                      ./_weather.py with its tests on ./_json/forecasts.json
#   weather-backtest   the replay of those rules over settled days, within
#                      the strategy's declared limits (sample days in
#                      ./_json/backtest-days.json)
#
#   packages.weather-backtest   the binaries; the tests run as they build
#   checks.weather-backtest     the same build: every crate's tests pass
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
        # The rule tests read the strategy's own fixture; the replay's tests
        # read the sample days.
        FIXTURE_PATH = ./_json/forecasts.json;
        DAYS_PATH = ./_json/backtest-days.json;
        meta.mainProgram = "weather-backtest";
      };
    in
    {
      packages.weather-backtest = crate;
      checks.weather-backtest = crate;
    };
}
