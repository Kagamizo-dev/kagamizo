# `nix flake check` type-checks every declaration and shows the result:
# entities, their domains and mailboxes, as JSON.
{ config, ... }:
{
  perSystem =
    { pkgs, ... }:
    {
      checks.identity = pkgs.writeText "identity.json" (
        builtins.toJSON {
          inherit (config.identity.checked) entities domains;
          cloudflare = removeAttrs config.cloudflare.checked [ "tokens" ];
          inherit (config.proton) vaults;
        }
      );
    };
}
