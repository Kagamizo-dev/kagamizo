# The standard shape of every legal identity, person or company: what it is
# (identity.entities.<e>.legal) and the accounts that make it run. Each
# provider names the roles its accounts fill (accounts.roles); each kind of
# entity requires some of them, so a new company is declared with all of
# its slots, planned or open, before anything is signed up for.
#
#   nix run .#identity-status   every entity, its legal record and its slots
#
#   llc, nonprofit   registered-agent, bank, a domain (or candidates)
#   person           passwords
#
# A slot is filled by a held account the entity owns, at any status, so a
# planned account counts: the declaration is the plan. An organization's
# registeredAgent must be one of its own registered-agent accounts.
{ lib, config, ... }:
let
  inherit (lib) mkOption types;
  inherit (config.identity.checked) entities domains;
  held = config.accounts.held;
  roles = [
    "bank"
    "brokerage"
    "registered-agent"
    "registrar"
    "mail"
    "passwords"
    "code"
    "hosting"
    "models"
    "research"
    "credit"
  ];
  required =
    kind:
    if kind == "person" then
      [ "passwords" ]
    else
      [
        "registered-agent"
        "bank"
      ];

  rolesOf = a: config.accounts.roles.${a.provider} or [ ];
  slots =
    name:
    lib.genAttrs roles (
      role:
      lib.mapAttrs (_: a: a.status) (
        lib.filterAttrs (_: a: a.owner == name && lib.elem role (rolesOf a)) held
      )
    );
  domainsOf = name: lib.attrNames (lib.filterAttrs (_: d: d.entity == name) domains);

  problems = lib.concatLists (
    lib.mapAttrsToList (
      name: e:
      let
        s = slots name;
        ra = e.legal.registeredAgent;
      in
      map (r: "identity.entities.${name}: a ${e.kind} needs a ${r} account; none is declared") (
        lib.filter (r: s.${r} == { }) (required e.kind)
      )
      ++ lib.optional (
        e.kind != "person" && domainsOf name == [ ] && e.domainCandidates == [ ]
      ) "identity.entities.${name}: an organization needs a domain, or domainCandidates to buy one from"
      ++
        lib.optional (ra != null && !(s.registered-agent ? ${ra}))
          "identity.entities.${name}.legal.registeredAgent: ${ra} is not a registered-agent account ${name} owns"
    ) entities
  );

  status = lib.mapAttrs (name: e: {
    inherit (e) legalName kind legal;
    domains = domainsOf name;
    inherit (e) domainCandidates;
    slots = lib.filterAttrs (_: v: v != { }) (slots name);
    missing = lib.filter (r: (slots name).${r} == { }) (required e.kind);
  }) entities;
in
{
  options.accounts.roles = mkOption {
    type = types.attrsOf (types.listOf (types.enum roles));
    default = { };
    description = "The roles a provider's accounts fill for their owner.";
  };

  config.perSystem =
    { pkgs, ... }:
    {
      packages.identity-status = pkgs.writeShellApplication {
        name = "identity-status";
        runtimeInputs = [ pkgs.jq ];
        text = ''
          jq -r 'def pad: . + ":" + (" " * (18 - length));
            to_entries[] | .value as $e |
            "\(.key): \($e.legalName) (\($e.kind)), \($e.legal.status)"
            + (if $e.legal.jurisdiction then " in \($e.legal.jurisdiction)" else "" end)
            + (if $e.legal.formed then " since \($e.legal.formed)" else "" end)
            + (if $e.kind == "person" then "" else ", EIN \($e.legal.ein)" end),
            "  \("domains" | pad)\(if $e.domains != [] then $e.domains | join(", ")
              elif $e.domainCandidates != [] then "none yet; candidates \($e.domainCandidates | join(", "))"
              else "none" end)",
            ($e.slots | to_entries[] | "  \(.key | pad)\(.value | to_entries | map("\(.key) (\(.value))") | join(", "))"),
            ($e.missing[] | "  \("MISSING" | pad)\(.)"),
            ""' <<<${lib.escapeShellArg (builtins.toJSON status)}
        '';
      };

      checks.lifecycle =
        assert lib.assertMsg (problems == [ ]) (lib.concatStringsSep "\n" problems);
        pkgs.writeText "lifecycle.json" (builtins.toJSON status);
    };
}
