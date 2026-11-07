# Who owns what, typed and transparent (the owner's ask, 2026-11-04): every
# area of work is one of an entity's mailbox roles (identity.domains.*.
# mailboxes), owned by one agent team of that entity, reviewed by other
# teams of it, and signed off by the entity's controller. Delegation reads
# this map; the homepage shows it; Lean proves its shape.
#
#   organization.areas.<entity>.<mailbox or mailbox+tag> = {
#                     # a plus-tag (dev+design) is a role on a mailbox that
#                     # costs no address: Proton routes it to the mailbox
#     owner;          # a governance.agents name serving the entity, or null
#                     # (the person's own: zach@)
#     reviewers;      # teams of the entity that review, never the owner
#     changeClasses;  # what the area may propose (subset of the owner's)
#     purpose;
#   }
#
# checks.organization-areas (./_lean/Areas.lean): no team reviews its own
# work, an area proposes only what its owner may, and every change class
# someone may merge is owned by some area.
{ lib, config, ... }:
let
  inherit (lib) mkOption types;
  cfg = config.organization.areas;
  agents = config.governance.agents;
  domains = config.identity.checked.domains;
  entities = config.identity.checked.entities;
  q = builtins.toJSON;
  # Each entity's mailboxes, from its domains.
  mailboxesOf =
    e: lib.concatLists (lib.mapAttrsToList (_: d: lib.optionals (d.entity == e) d.mailboxes) domains);
  area =
    entity:
    types.submodule {
      options = {
        owner = mkOption {
          type = types.nullOr (types.enum (lib.attrNames agents));
          default = null;
        };
        reviewers = mkOption {
          type = types.listOf (types.enum (lib.attrNames agents));
          default = [ ];
        };
        changeClasses = mkOption {
          type = types.listOf (types.enum (lib.attrNames config.governance.changeClasses));
          default = [ ];
        };
        purpose = mkOption { type = types.str; };
        controller = mkOption {
          type = types.str;
          readOnly = true;
          default =
            if entities.${entity}.kind == "person" then
              entity
            else
              lib.head config.governance.controllers.${entity};
          description = "Who signs off: the entity's controller, or the person themself.";
        };
      };
    };
  flat = lib.concatLists (
    lib.mapAttrsToList (
      entity: areas:
      lib.mapAttrsToList (
        mailbox: a:
        a
        // {
          inherit entity mailbox;
          ownerClasses = if a.owner == null then [ ] else agents.${a.owner}.changeClasses;
        }
      ) areas
    ) cfg
  );
  problems = lib.concatMap (
    a:
    let
      at = "organization.areas.${a.entity}.${a.mailbox}";
      serves = n: agents.${n}.serves == a.entity;
    in
    lib.optional (
      !lib.elem (lib.head (lib.splitString "+" a.mailbox)) (mailboxesOf a.entity)
    ) "${at}: ${a.entity} has no mailbox ${lib.head (lib.splitString "+" a.mailbox)}"
    ++ lib.optional (
      a.owner != null && !serves a.owner
    ) "${at}: owner ${a.owner} does not serve ${a.entity}"
    ++ map (r: "${at}: reviewer ${r} does not serve ${a.entity}") (
      lib.filter (r: !serves r) a.reviewers
    )
  ) flat;
  mergeable = lib.attrNames (
    lib.filterAttrs (_: c: c.merge != "never") config.governance.changeClasses
  );
  rendered = ''
    namespace Kagamizo.Areas

    /-- Every area, rendered by modules/organization/areas.nix. -/
    def areas : List Area := [
    ${lib.concatMapStringsSep ",\n" (
      a:
      "  { entity := ${q a.entity}, mailbox := ${q a.mailbox}, owner := ${
          if a.owner == null then "none" else "some ${q a.owner}"
        }, reviewers := [${lib.concatMapStringsSep ", " q a.reviewers}], classes := [${
          lib.concatMapStringsSep ", " q a.changeClasses
        }], ownerClasses := [${lib.concatMapStringsSep ", " q a.ownerClasses}] }"
    ) flat}
    ]

    /-- The change classes someone may merge (modules/governance). -/
    def mergeable : List String := [${lib.concatMapStringsSep ", " q mergeable}]

    /-- No team reviews its own work. -/
    theorem all_separated : areas.all Area.separated = true := by decide +kernel

    /-- Every area proposes only what its owner may. -/
    theorem all_scoped : areas.all Area.scoped = true := by decide +kernel

    /-- Every mergeable class is owned by some area. -/
    theorem all_covered : mergeable.all (covered areas) = true := by decide +kernel

    end Kagamizo.Areas
  '';
in
{
  options.organization.areas = mkOption {
    type = types.submodule {
      options = lib.mapAttrs (
        entity: _:
        mkOption {
          type = types.attrsOf (area entity);
          default = { };
          description = "${entity}'s areas, one per mailbox role.";
        }
      ) entities;
    };
    default = { };
    description = "entity -> mailbox -> area.";
  };

  config = {
    organization.areas = {
      jingzo = {
        admin = {
          owner = "governance-jingzo";
          reviewers = [ "legal-jingzo" ];
          purpose = "the company's accounts and their records";
        };
        finance = {
          owner = "accounting-jingzo";
          reviewers = [
            "governance-jingzo"
            "legal-jingzo"
          ];
          purpose = "banking, brokerage, cards and the books";
        };
        legal = {
          owner = "legal-jingzo";
          reviewers = [ "governance-jingzo" ];
          purpose = "the registered agent, the state, the IRS";
        };
        research = {
          owner = "research-jingzo";
          reviewers = [
            "accounting-jingzo"
            "governance-jingzo"
          ];
          changeClasses = [ "content" ];
          purpose = "the research-to-trade loop's research and its published results";
        };
        dev = {
          owner = "governance-jingzo";
          purpose = "the company's code accounts (planned)";
        };
        automations = {
          owner = "governance-jingzo";
          purpose = "automated mail and signups: routed, never read by a person";
        };
      };
      kagamizo = {
        zach = {
          purpose = "the face of the company: the owner's own";
        };
        admin = {
          owner = "governance-kagamizo";
          reviewers = [ "legal-kagamizo" ];
          purpose = "SaaS and tool accounts, the GitHub organization";
        };
        billing = {
          owner = "accounting-kagamizo";
          reviewers = [ "governance-kagamizo" ];
          purpose = "invoices and payments";
        };
        legal = {
          owner = "legal-kagamizo";
          reviewers = [ "governance-kagamizo" ];
          purpose = "the registered agent, state filings, the IRS";
        };
        dev = {
          owner = "upkeep";
          reviewers = [
            "review"
            "design"
          ];
          changeClasses = [
            "tool"
            "code"
          ];
          purpose = "the repository: pins, tooling, code; reviewed before the owner approves";
        };
        "dev+design" = {
          owner = "design";
          reviewers = [
            "review"
            "upkeep"
          ];
          changeClasses = [
            "page-design"
            "content"
          ];
          purpose = "every page's layout and the design system, checked on a phone and a desktop";
        };
        automations = {
          owner = "governance-kagamizo";
          purpose = "automated mail, events and signups: routed, never read";
        };
      };
      mirazo = {
        # The person's own area: their accounts and money are theirs alone;
        # the twin of their inventory and devices is the twin team's work.
        zach = {
          owner = "twin";
          reviewers = [
            "builders"
            "accounting-mirazo"
            "legal-mirazo"
            "governance-mirazo"
          ];
          changeClasses = [
            "content"
            "mod"
          ];
          purpose = "the person: their accounts, money and devices, and the digital twin of their inventory";
        };
        automations = {
          owner = "governance-mirazo";
          purpose = "automated mail and the catch-all";
        };
      };
    };

    governance.problems = problems;

    perSystem =
      { pkgs, ... }:
      {
        checks.organization-areas =
          assert lib.assertMsg (problems == [ ]) (lib.concatStringsSep "\n" problems);
          pkgs.runCommand "organization-areas"
            {
              nativeBuildInputs = [ pkgs.lean4 ];
              facts = rendered;
              passAsFile = [ "facts" ];
            }
            ''
              cat ${./_lean/Areas.lean} "$factsPath" > Check.lean
              lean Check.lean
              touch $out
            '';
      };
  };
}
