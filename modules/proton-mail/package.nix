# The `proton-mail` binary (./_src): Proton Mail domains and addresses on
# Proton's own go-proton-api. The `mail` command (./mail.nix) drives it.
{
  perSystem =
    { pkgs, ... }:
    {
      packages.proton-mail = pkgs.buildGoModule {
        pname = "proton-mail";
        version = "0.1.0";
        src = ./_src;
        vendorHash = "sha256-1mmrX9U4Za+ar8I1njx5eHm6eZOrFfJvh8Ws6a7ddH8=";
        env.CGO_ENABLED = "0";
        meta.mainProgram = "proton-mail";
      };
    };
}
