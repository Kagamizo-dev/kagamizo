# The weather backtest (the research team's, 2026-11-06): a Rust port of
# the weather rules (./_weather.py's probability and edge, with its test
# fixtures) that replays a day's forecast, the observed outcome the
# contract settles on, and the contract's prices, within the strategy's
# declared limits. Sources sit behind a trait: the fixtures in tests, the
# live forecasts, NWS climate reports and Kalshi prices on jingzo-host.
#
#   packages.weather-backtest   the binary; its tests run as it builds
#   checks.weather-backtest     the same build: the ported rules' tests pass
{
  perSystem =
    { pkgs, ... }:
    let
      crate = pkgs.rustPlatform.buildRustPackage {
        pname = "weather-backtest";
        version = "0.1.0";
        src = ./_weather-backtest;
        cargoLock.lockFile = ./_weather-backtest/Cargo.lock;
        doCheck = true;
        # The tests read the strategy's own fixture, the same file the Python
        # rules are tested on.
        FIXTURE_PATH = ./_json/forecasts.json;
        meta.mainProgram = "weather-backtest";
      };
    in
    {
      packages.weather-backtest = crate;
      checks.weather-backtest = crate;
    };
}
