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

      # From its tagged source, patched (./_patches/secretspec-protonpass.patch)
      # in its Proton Pass provider: item and share ids are passed as
      # --flag=value (an id starting with '-' read as a flag, so overwriting
      # a secret failed); and a `field` coordinate reads that field of an
      # item (a custom item's extra field, such as an API credential's
      # Secret, or a login's own field) instead of the note body. Writing
      # into a field is refused: the owner places those.
      secretspec = pkgs.rustPlatform.buildRustPackage {
        pname = "secretspec";
        version = "0.21.1";
        src = inputs.secretspec-src;
        patches = [ ./_patches/secretspec-protonpass.patch ];
        cargoLock.lockFile = "${inputs.secretspec-src}/Cargo.lock";
        cargoBuildFlags = [
          "-p"
          "secretspec"
        ];
        # Most of its tests reach real providers; the Proton Pass provider's
        # own run offline and cover the patch.
        cargoTestFlags = [
          "-p"
          "secretspec"
          "--lib"
        ];
        checkFlags = [ "provider::protonpass" ];
        meta.mainProgram = "secretspec";
      };
    in
    {
      packages = { inherit pass-cli secretspec; };
    };
}
