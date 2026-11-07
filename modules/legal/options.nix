# The legal record of every entity, typed: what each company is (its
# purpose, who owns and runs it, where and when it was formed, its EIN, its
# registered agent, the documents it holds), so any document a bank, a
# broker or the IRS asks for is generated from the declarations and a
# Proton Pass sign-in. This repo is public, so the record names *where* each
# private value lives (a Proton Pass item in the entity's vault), never the
# value: the EIN, the filing number and the state and date of formation are
# read through `secretspec run --profile legal` at render time only.
#
#   legal.records.<entity> = {
#     purpose;                        # public text
#     organization = { management; members = [ { entity; percent; } ]; managers; }
#     formation = { state; item; }    # state when it is the plan (public);
#                                     # item: the api-credential item holding
#                                     # the filing number (Secret) and
#                                     # "US-XX YYYY-MM-DD" (Permissions)
#     ein = { item; }                 # the api-credential item holding the EIN
#     registeredAgent;                # the northwest-<e> account
#     addresses = { registeredOffice; mailing; }   # public text or null
#     documents.<name> = { kind; title; where = { vault; item; }; issued; }
#   }
#
#   nix run .#legal-prepare           the Proton Pass items the owner fills
#   nix run .#legal-documents         render a document from the record
#   nix run .#legal-sync              Northwest's view of the record, as JSON
#   checks.legal-record               Lean: every record complete for its status
#                                     (./_lean/Record.lean); every template renders
#
# Sending: the legal@ areas exist (modules/organization) but agents cannot
# send mail yet (a Gap, modules/cloudflare/README.md), so rendered documents
# go to Proton Drive or the Matrix room for now.
{ lib, config, ... }:
let
  inherit (lib) mkOption types;
  top = config;
  inherit (config.identity.checked) entities;
  secret = import ../_lib/secret.nix;
  entityNames = lib.attrNames entities;
  usState = types.strMatching "US-[A-Z]{2}";
  date = types.strMatching "[0-9]{4}-[0-9]{2}-[0-9]{2}";
  # Proton Pass item titles: lowercase, dashes.
  itemTitle = types.strMatching "[a-z0-9][a-z0-9-]*";
  documentKinds = [
    "formation" # articles or certificate of formation / organization
    "operating-agreement"
    "ein-letter" # IRS CP 575
    "agent-acceptance" # the registered agent's consent
    "annual-report"
    "other"
  ];

  record =
    { name, ... }:
    let
      e = entities.${name};
    in
    {
      options = {
        purpose = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "The business purpose, public text; a person has none.";
        };
        organization = mkOption {
          type = types.nullOr (
            types.submodule {
              options = {
                management = mkOption {
                  type = types.enum [
                    "member-managed"
                    "manager-managed"
                  ];
                };
                members = mkOption {
                  type = types.listOf (
                    types.submodule {
                      options = {
                        entity = mkOption { type = types.enum entityNames; };
                        percent = mkOption { type = types.ints.between 1 100; };
                      };
                    }
                  );
                  description = "Who owns it; the percents sum to 100.";
                };
                managers = mkOption {
                  type = types.listOf (types.enum entityNames);
                  default = [ ];
                  description = "Set exactly when manager-managed.";
                };
              };
            }
          );
          default = null;
        };
        formation = {
          state = mkOption {
            type = types.nullOr usState;
            default = e.legal.jurisdiction;
            description = "Where it is or will be formed, when that is public (the plan); else in the item.";
          };
          item = mkOption {
            type = types.nullOr itemTitle;
            default = null;
            description = "The api-credential item: filing number as Secret, `US-XX YYYY-MM-DD` as Permissions.";
          };
        };
        ein.item = mkOption {
          type = types.nullOr itemTitle;
          default = null;
          description = "The api-credential item whose Secret is the EIN.";
        };
        registeredAgent = mkOption {
          type = types.nullOr types.str;
          default = e.legal.registeredAgent;
          description = "The registered-agent account (accounts.held).";
        };
        addresses = {
          registeredOffice = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "The registered office, public text (the agent's published office).";
          };
          mailing = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "A public mailing address, or null: a private one stays in Proton Pass.";
          };
        };
        taxClassification = mkOption {
          type = types.nullOr types.str;
          readOnly = true;
          default = top.money.tax.${name}.classification or null;
          description = "From money.tax, when stated.";
        };
        documents = mkOption {
          type = types.attrsOf (
            types.submodule {
              options = {
                kind = mkOption { type = types.enum documentKinds; };
                title = mkOption { type = types.str; };
                where = {
                  vault = mkOption {
                    type = types.str;
                    default = e.vault;
                  };
                  item = mkOption {
                    type = itemTitle;
                    description = "The note item the document is attached to, or whose note is its Proton Drive link.";
                  };
                };
                issued = mkOption {
                  type = types.nullOr date;
                  default = null;
                  description = "When it was issued, when public; null when only the document says.";
                };
              };
            }
          );
          default = { };
        };
      };
    };

  cfg = config.legal.records;

  sumOf = o: lib.foldl' (n: m: n + m.percent) 0 o.members;
  problems = lib.concatLists (
    lib.mapAttrsToList (
      name: r:
      let
        e = entities.${name};
        at = "legal.records.${name}";
        o = r.organization;
      in
      lib.optional (!(entities ? ${name})) "${at}: no such entity"
      ++ lib.optional (e.kind == "person" && o != null) "${at}.organization: a person has no organization"
      ++ lib.optionals (o != null) (
        lib.optional (
          o.members == [ ]
        ) "${at}.organization.members: an organization has at least one member"
        ++ lib.optional (
          sumOf o != 100
        ) "${at}.organization.members: the percents sum to ${toString (sumOf o)}, not 100"
        ++ lib.optional (
          !lib.allUnique (map (m: m.entity) o.members)
        ) "${at}.organization.members: an entity is listed twice"
        ++ lib.optional (
          (o.management == "manager-managed") != (o.managers != [ ])
        ) "${at}.organization.managers: set exactly when manager-managed"
      )
      ++ lib.optional (
        r.ein.item != null
        && lib.elem e.legal.ein [
          "none"
          "not-applicable"
        ]
      ) "${at}.ein.item: identity says ${name} has no EIN (legal.ein = ${e.legal.ein})"
      ++ lib.optional (
        r.registeredAgent != null && !(config.accounts.held ? ${r.registeredAgent})
      ) "${at}.registeredAgent: no account ${r.registeredAgent}"
      ++ lib.optional (
        r.formation.item != null && e.legal.status == "planned"
      ) "${at}.formation.item: nothing is filed for a planned entity"
    ) cfg
  );

  checked =
    assert lib.assertMsg (problems == [ ]) (
      "modules/legal:\n" + lib.concatMapStrings (p: "  - ${p}\n") problems
    );
    lib.mapAttrs (
      name: r:
      r
      // {
        inherit (entities.${name}) legalName kind;
        status = entities.${name}.legal.status;
        domains = lib.attrNames (lib.filterAttrs (_: d: d.entity == name) config.identity.checked.domains);
      }
    ) cfg;

  upper = s: lib.toUpper (lib.replaceStrings [ "-" ] [ "_" ] s);
  llcs = lib.filterAttrs (_: r: r.kind != "person") checked;
in
{
  options.legal = {
    records = mkOption {
      type = types.attrsOf (types.submodule record);
      default = { };
      description = "Each entity's legal record; values that are private name their Proton Pass item.";
    };
    checked = mkOption {
      type = types.raw;
      readOnly = true;
      description = "The records with the entity's name, kind, status and domains, once every rule holds.";
    };
    documentKinds = mkOption {
      type = types.listOf types.str;
      readOnly = true;
      default = documentKinds;
    };
    # The environment variable each private value arrives in, per entity.
    variables = mkOption {
      type = types.raw;
      readOnly = true;
      default = lib.mapAttrs (name: _: {
        ein = "EIN_${upper name}";
        filingNumber = "FILING_NUMBER_${upper name}";
        formed = "FORMED_${upper name}";
      }) llcs;
    };
  };

  config = {
    legal.checked = checked;

    # The owner's declarations.
    legal.records = {
      # QSearch LLC, formed before this repo: its state, date, filing number
      # and EIN are on file with Northwest and the IRS, and in Proton Pass
      # once pasted (`legal-prepare`); never here.
      jingzo = {
        purpose = "Algorithmic trading research and published research: income from what runs by itself, nothing sold by appointment (the owner's decision, 2026-10-31).";
        organization = {
          management = "member-managed";
          members = [
            {
              entity = "mirazo";
              percent = 100;
            }
          ];
        };
        formation.item = "formation-jingzo";
        ein.item = "ein-jingzo";
        documents = {
          articles = {
            kind = "formation";
            title = "Articles of Organization, QSearch LLC";
            where.item = "doc-articles-jingzo";
          };
          ein-letter = {
            kind = "ein-letter";
            title = "IRS CP 575, EIN assignment, QSearch LLC";
            where.item = "doc-ein-letter-jingzo";
          };
          operating-agreement = {
            kind = "operating-agreement";
            title = "Operating Agreement, QSearch LLC (single member)";
            where.item = "doc-operating-agreement-jingzo";
          };
        };
      };
      # Kagamizo LLC, to be formed in Wyoming by Northwest: the plan is the
      # record until the formation is filed.
      kagamizo = {
        purpose = "Software, automation and the owner's professional work, run as code: no client contracts, nothing sold by appointment (the owner's decision, 2026-10-31).";
        organization = {
          management = "member-managed";
          members = [
            {
              entity = "mirazo";
              percent = 100;
            }
          ];
        };
      };
      # The person: the root of both companies; a natural person's record
      # holds nothing but the slot (their own papers are in their vault).
      mirazo = { };
    };

    # The private values, one api-credential item each in the entity's vault
    # (its `-logins` provider), filled by the owner: an identifier the IRS
    # or the state issues on paper is a console credential on the boundary.
    secrets.profiles.legal = {
      defaults.providers = [ "root" ];
    }
    // lib.concatMapAttrs (
      name: r:
      let
        v = config.legal.variables.${name};
        own = {
          providers = [ "${name}-logins" ];
          required = false;
        };
      in
      lib.optionalAttrs (r.ein.item != null) {
        ${v.ein} =
          secret {
            kind = "identifier";
            issuer = "human:console-credential";
            description = "${r.legalName}'s EIN, as 12-3456789";
            item = r.ein.item;
            template = "api-credential";
            field = "Secret";
          }
          // own;
      }
      // lib.optionalAttrs (r.formation.item != null) {
        ${v.filingNumber} =
          secret {
            kind = "identifier";
            issuer = "human:console-credential";
            description = "${r.legalName}'s formation filing number with its state";
            item = r.formation.item;
            template = "api-credential";
            field = "Secret";
          }
          // own;
        ${v.formed} =
          secret {
            kind = "identifier";
            issuer = "human:console-credential";
            description = "${r.legalName}'s state and date of formation, as US-XX YYYY-MM-DD";
            item = r.formation.item;
            template = "api-credential";
            field = "Permissions";
          }
          // own;
      }
    ) llcs;

    # Reading the record off Northwest (./sync.nix) needs its company
    # records, filings and documents.
    accounts.demands = lib.concatLists (
      lib.mapAttrsToList (
        name: r:
        lib.optionals (r.registeredAgent != null) (
          map
            (capability: {
              account = r.registeredAgent;
              inherit capability;
              need = true;
              why = "legal-sync reads ${name}'s record off its registered agent";
            })
            [
              "companyRecords"
              "filingStatus"
              "documents"
            ]
        )
      ) llcs
    );
  };
}
