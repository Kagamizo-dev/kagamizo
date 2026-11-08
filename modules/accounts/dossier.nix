# Every account as a typed vault item (the owner's rule, 2026-11-08): what
# a provider asks for at sign-up, field by field, and where each comes from.
# The agents prepare the account's Proton Pass item through pass-cli with
# every field that is not truly human, from the owner's Proton identity and
# the legal record (values live only in Proton, never here); the owner only
# authenticates: the password or passkey, second factors, a liveness check,
# and approving the submission (its terms and attestations).
#
#   accounts.dossierFields.<f>  a field providers ask for: whose it is, and
#                               where it comes from, or that it is human
#   accounts.dossiers.<a>       an account's sign-up: the provider, whose
#                               account (person or entity), and the fields
#                               it requires
#
# The rule (checked here): every field an account requires is in the
# catalogue, and of the account's kind (a person's account asks only for
# personal fields and the account's own).
{ lib, config, ... }:
let
  inherit (lib) mkOption types;
  cfg = config.accounts;
  field = types.submodule {
    options = {
      of = mkOption {
        type = types.enum [
          "person"
          "entity"
          "account"
        ];
      };
      human = mkOption {
        type = types.bool;
        default = false;
        description = "Truly human: left to the owner, never prepared.";
      };
      from = mkOption {
        type = types.str;
        description = "Where the agents take it from, or why it is the owner's.";
      };
    };
  };
  person = from: {
    of = "person";
    inherit from;
  };
  entity = from: {
    of = "entity";
    inherit from;
  };
  human = of: from: {
    inherit of from;
    human = true;
  };
in
{
  options.accounts = {
    dossierFields = mkOption {
      type = types.attrsOf field;
      default = { };
    };
    dossiers = mkOption {
      type = types.attrsOf (
        types.submodule {
          options = {
            provider = mkOption { type = types.str; };
            kind = mkOption {
              type = types.enum [
                "person"
                "entity"
              ];
            };
            entity = mkOption { type = types.enum (lib.attrNames config.identity.entities); };
            requires = mkOption {
              type = types.listOf (types.enum (lib.attrNames cfg.dossierFields));
            };
            source = mkOption { type = types.str; };
          };
        }
      );
      default = { };
      description = "Each account's sign-up, as the fields it requires (researched from the provider's own pages).";
    };
  };

  config = {
    accounts.dossierFields = {
      # The person's.
      legal-name = person "the owner's identity record (identity.entities.mirazo)";
      date-of-birth = person "the owner's Proton Pass identity item";
      citizenship = person "the owner's Proton Pass identity item";
      ssn = person "the owner's Proton Pass identity item";
      residential-address = person "the owner's Proton Pass identity item";
      proof-of-address = person "a statement in Proton Drive (Mercury's, by API)";
      id-document = person "the passport's scan in Proton Drive (legal.records.mirazo.documents.passport)";
      employment = person "the resume (legal.records.mirazo.documents.resume)";
      income-and-net-worth = person "the bank's balances (bank-book) and the W-2s";
      investment-objectives = person "the bank's declared strategies and limits";
      trading-experience = person "the trading ledger: products, years, trades a year";
      regulatory-flags = person "the owner's statement in their identity item (no broker-dealer or exchange affiliation, no insider role)";
      # The entity's.
      entity-name-and-ein = entity "the legal record (legal.records.<entity>, the EIN's Pass item)";
      formation-documents = entity "the articles in Proton Drive (legal.records.<entity>.documents.articles)";
      good-standing = entity "a certificate from the state, read through the registered agent (Northwest)";
      operating-agreement = entity "the operating agreement in Proton Drive";
      ein-letter = entity "the IRS CP 575 in Proton Drive";
      registered-agent-and-address = entity "the legal record and Northwest";
      business-description = entity "the legal record's purpose";
      beneficial-owners = entity "the legal record's members (the owner, 100%)";
      source-of-funds = entity "the bank's declared flows";
      entity-bank-statement = entity "Mercury's statement, by API";
      # The account's own.
      login-email = {
        of = "account";
        from = "the account's address on its owner's domain (a Pass alias)";
      };
      handle = {
        of = "account";
        from = "generated into the account's Pass item";
      };
      api-key-slot = {
        of = "account";
        from = "an empty field in the account's Pass item, for the key the provider issues";
      };
      # The owner's alone.
      password-or-passkey = human "account" "set by the owner into the Pass item";
      second-factor = human "account" "registered by the owner (passkey, authenticator; never SMS alone)";
      liveness-check = human "person" "a selfie or video only the owner can give";
      submission-approval = human "account" "the owner approves the terms, disclosures and attestations, once, as one approval";
    };

    # No account is waiting to be opened (Kraken was set aside on 2026-11-08:
    # Public's own crypto covers every hour).
    accounts.dossiers = { };

    governance.problems = lib.concatLists (
      lib.mapAttrsToList (
        a: d:
        map
          (f: "accounts.dossiers.${a}: ${f} is ${cfg.dossierFields.${f}.of}'s, not a ${d.kind}'s account's")
          (
            lib.filter (
              f:
              let
                of = cfg.dossierFields.${f}.of;
              in
              of != "account" && of != d.kind
            ) d.requires
          )
      ) cfg.dossiers
    );
  };
}
