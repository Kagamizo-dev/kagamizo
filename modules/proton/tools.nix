# pass-cli and secretspec, pinned to releases newer than nixpkgs carries:
# pass-cli 2.1+ for agent tokens, secretspec 0.19+ for current pass-cli.
# Hashes match each project's published .sha256 file.
{ inputs, ... }:
{
  perSystem =
    { pkgs, ... }:
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

      # From its tagged source, patched: its Proton Pass provider passes item
      # and share ids as separate arguments, and an id starting with '-'
      # (they are URL-safe base64) reads to pass-cli as a flag, so writing a
      # secret that already exists failed.
      secretspec = pkgs.rustPlatform.buildRustPackage {
        pname = "secretspec";
        version = "0.21.1";
        src = inputs.secretspec-src;
        patches = [ ./_patches/secretspec-ids-as-values.patch ];
        cargoLock.lockFile = "${inputs.secretspec-src}/Cargo.lock";
        cargoBuildFlags = [
          "-p"
          "secretspec"
        ];
        # Its tests reach real providers.
        doCheck = false;
        meta.mainProgram = "secretspec";
      };
    in
    {
      packages = { inherit pass-cli secretspec; };
    };
}
