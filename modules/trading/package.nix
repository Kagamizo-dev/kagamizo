# NautilusTrader, the trading engine: backtests, paper and live nodes on one
# event-driven core. Pinned to 1.231.0, the last stable release (2026-08-02;
# 2.x is a release candidate its own docs keep away from live money), from
# its published wheel rather than a source build, which needs a pinned Rust
# toolchain. A few dependencies are pinned a little ahead of this nixpkgs;
# the backtest check (./check.nix) proves the engine runs on these.
_: {
  perSystem =
    { pkgs, ... }:
    let
      py = pkgs.python313Packages;
    in
    {
      packages.nautilus-trader = py.buildPythonPackage rec {
        pname = "nautilus_trader";
        version = "1.231.0";
        format = "wheel";
        src = pkgs.fetchurl {
          url = "https://files.pythonhosted.org/packages/29/51/a887526a76891c67370622aace657b6a9d7bfee02ea52e005ed2fb8c5285/${pname}-${version}-cp313-cp313-manylinux_2_35_x86_64.whl";
          hash = "sha256-Qp6mHDOjLNhJjTng6pXrqhK42/wlxx+6uoRfKwXoq5E=";
        };
        nativeBuildInputs = [ pkgs.autoPatchelfHook ];
        buildInputs = [ pkgs.stdenv.cc.cc.lib ];
        dependencies = with py; [
          click
          fsspec
          msgspec
          numpy
          pandas
          portion
          pyarrow
          pytz
          tqdm
          tzdata
          uvloop
        ];
        pythonRelaxDeps = true;
        dontCheckRuntimeDeps = true;
        pythonImportsCheck = [
          "nautilus_trader"
          "nautilus_trader.backtest.engine"
        ];
        meta.platforms = [ "x86_64-linux" ];
      };
    };
}
