# The identity model as nix-effects types. Every declaration under
# config.identity and config.cloudflare is checked against these at eval time,
# and a failure names the exact field that broke.
#
# Identity is a dependent record: the type of `domains` is computed from the
# value of `entities`, so a domain can only belong to an entity that exists.
{ lib, fx }:
let
  inherit (fx.types)
    Record
    ListOf
    Maybe
    String
    Attrs
    Null
    refined
    DepRecord
    ;

  matches = re: s: builtins.match re s != null;

  NonEmpty = refined "NonEmptyString" String (s: s != "");
  Hex32 = refined "CloudflareId" String (matches "[0-9a-f]{32}");
  Fqdn = refined "DomainName" String (matches "([a-z0-9]([a-z0-9-]*[a-z0-9])?\\.)+[a-z]{2,}");
  LocalPart = refined "MailboxName" String (matches "[a-z0-9]([a-z0-9.-]*[a-z0-9])?");
  VaultName = refined "VaultName" String (matches "[A-Za-z0-9][A-Za-z0-9 _-]*");
  Timestamp = refined "Rfc3339Utc" String (
    matches "[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z"
  );
  oneOf = name: xs: refined name String (s: builtins.elem s xs);

  # At most seven addresses per domain, each once. An eighth means a new domain.
  Mailboxes = refined "AtMostSevenMailboxes" (ListOf LocalPart) (
    l: builtins.length l <= 7 && lib.allUnique l
  );

  Entity = Record {
    legalName = NonEmpty;
    kind = oneOf "EntityKind" [
      "person"
      "llc"
      "nonprofit"
    ];
    # Proton Pass vault holding this entity's logins.
    vault = VaultName;
    # Names to check with `nix run .#registrar -- check` before buying one.
    domainCandidates = ListOf Fqdn;
  };

  ProtonMail = Record {
    verification = NonEmpty;
    dkimId = NonEmpty;
  };

  # A dependent type: a domain's record type is computed from its own zoneId.
  # Without a zone there is nowhere to put DNS, so proton must be null and
  # records empty.
  Domain =
    entityNames: d:
    let
      zoned = d.zoneId or null != null;
    in
    Record {
      entity = oneOf "DeclaredEntity" entityNames;
      zoneId = Maybe Hex32;
      registrar = oneOf "Registrar" [
        "cloudflare"
        "external"
      ];
      mailboxes = Mailboxes;
      proton = if zoned then Maybe ProtonMail else Null;
      records = if zoned then Attrs else refined "NoRecordsWithoutZone" Attrs (r: r == { });
    };

  # Σ(entities). Σ(domainNames). domains, where each domain's owner must be
  # one of the declared entities.
  Identity =
    v:
    DepRecord [
      {
        name = "entities";
        type = Record (lib.mapAttrs (_: _: Entity) v.entities);
      }
      {
        name = "domainNames";
        type = ListOf Fqdn;
      }
      {
        name = "domains";
        type = p: Record (lib.mapAttrs (_: Domain (lib.attrNames p.entities)) v.domains);
      }
    ];

  Cloudflare = Record {
    accountId = Hex32;
    stateBucket = refined "R2BucketName" String (matches "[a-z0-9][a-z0-9-]{1,61}[a-z0-9]");
    tokenExpiry = Timestamp;
  };

  # Vaults holding the infra secrets, one per trust level (see secretspec.toml).
  InfraVaults = Record {
    root = VaultName;
    ci = VaultName;
    agents = VaultName;
  };

  errorsOf =
    type: value:
    (fx.handle {
      handlers = fx.effects.typecheck.collecting;
      state = [ ];
    } (type.validate value)).state;

  # The value itself when it checks, otherwise an error listing every failure.
  checked =
    what: type: value:
    let
      errors = errorsOf type value;
    in
    if errors == [ ] then
      value
    else
      throw "${what} does not type-check:\n${lib.concatMapStrings (e: "  - ${e.message}\n") errors}";
in
{
  # DepRecord checks the packed (nested Σ) form; hand back the plain attrset.
  identity =
    v:
    let
      T = Identity v;
    in
    builtins.seq (checked "identity" T (T.pack (v // { domainNames = lib.attrNames v.domains; }))) v;
  cloudflare = checked "cloudflare" Cloudflare;
  infraVaults = checked "proton.infraVaults" InfraVaults;
}
