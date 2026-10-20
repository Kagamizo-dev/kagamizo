# Tools for Claude sessions on this repo, pinned to releases newer than nixpkgs
# carries: pass-cli 2.1+ for agent tokens, secretspec 0.19+ for current pass-cli.
# Hashes match each project's published .sha256 file.
{
  pkgs,
  infra,
  registrar,
  proton,
}:
let
  pass-cli = pkgs.stdenv.mkDerivation rec {
    pname = "pass-cli";
    version = "2.4.2";
    src = pkgs.fetchurl {
      url = "https://github.com/protonpass/pass-cli/releases/download/${version}/pass-cli-linux-x86_64";
      hash = "sha256-QIm99ZgRQKxb7mXS15v5h2dTf1TTMZe3nl+GxjBxSEI=";
    };
    dontUnpack = true;
    nativeBuildInputs = [ pkgs.autoPatchelfHook ];
    buildInputs = [ pkgs.stdenv.cc.cc.lib ];
    installPhase = "install -Dm755 $src $out/bin/pass-cli";
  };

  # Static musl build, so nothing to patch.
  secretspec = pkgs.stdenvNoCC.mkDerivation rec {
    pname = "secretspec";
    version = "0.21.1";
    src = pkgs.fetchurl {
      url = "https://github.com/cachix/secretspec/releases/download/v${version}/secretspec-x86_64-unknown-linux-musl.tar.xz";
      hash = "sha256-R1EEG3A1hozqQZdKv+utinLruARukRUXnCwfquNWkek=";
    };
    installPhase = "install -Dm755 -t $out/bin secretspec";
  };
in
pkgs.symlinkJoin {
  name = "session-tools";
  paths = [
    pass-cli
    secretspec
    infra
    registrar
    proton
  ];
}
