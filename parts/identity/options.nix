# Who exists (entities), which domains they own, and the mailboxes on each.
# Any file in the tree can declare into these; the merged result is checked
# against ../_lib/types.nix and read by consumers as `identity.checked`.
#
#   identity.entities.<name> = { legalName; kind; vault; domainCandidates; };
#   identity.domains.<fqdn>  = { entity; zoneId; registrar; registration; mailboxes;
#                                proton; records; };
{
  lib,
  config,
  inputs,
  ...
}:
let
  inherit (lib) mkOption types;
  t = import ../_lib/types.nix {
    inherit lib;
    fx = inputs.nix-effects.lib;
  };
  cfg = config.identity;

  entityDefaults = {
    domainCandidates = [ ];
  };
  domainDefaults = {
    zoneId = null;
    registrar = "external";
    mailboxes = [ ];
    registration = null;
    proton = null;
    records = { };
  };
in
{
  options.identity = {
    entities = mkOption {
      type = types.attrsOf types.anything;
      default = { };
    };
    domains = mkOption {
      type = types.attrsOf types.anything;
      default = { };
    };
    checked = mkOption {
      type = types.raw;
      readOnly = true;
      description = "The declarations with defaults filled in, after type-checking.";
    };
  };

  config.identity.checked = t.identity {
    entities = lib.mapAttrs (_: e: entityDefaults // e) cfg.entities;
    domains = lib.mapAttrs (_: d: domainDefaults // d) cfg.domains;
  };
}
