# Claude session setup as code: the pinned session tools and the typed
# network allowlist rendered to the paste-ready form.
{ pkgs, infra }:
let
  inherit (pkgs) lib;
  inherit (lib.evalModules { modules = [ ./environment.nix ]; }) config;

  enabled = lib.filter (g: g.enable) (lib.attrValues config.network.allow);
  hosts = lib.unique (lib.sort lib.lessThan (lib.concatMap (g: g.hosts) enabled));
in
{
  tools = import ./tools.nix { inherit pkgs infra; };

  # One domain per line, exactly what the Allowed domains field takes. Pair it
  # with the "include default list" box set to network.includeDefaults.
  allowed-domains = pkgs.writeText "allowed-domains.txt" (lib.concatLines hosts);
  inherit (config.network) includeDefaults;
}
