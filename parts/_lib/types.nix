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

  Month = refined "YearMonth" String (matches "[0-9]{4}-(0[1-9]|1[0-2])");
  Usd = refined "UsdAmount" fx.types.Any (x: (builtins.isInt x || builtins.isFloat x) && x >= 0);

  # What buying a domain through Cloudflare cost, written down after
  # `registrar register`. It renews on the same month every year.
  Registration = Record {
    month = Month;
    costUsd = Usd;
    renewalUsd = Usd;
  };

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
      # Only domains bought through Cloudflare have a registration to budget.
      registration = if d.registrar or "" == "cloudflare" then Registration else Null;
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
    # Hard ceiling on Cloudflare spend per month, enforced by `registrar`.
    monthlyBudgetUsd = Usd;
  };

  # Vaults holding the infra secrets, one per trust level (see secretspec.toml).
  InfraVaults = Record {
    root = VaultName;
    ci = VaultName;
    agents = VaultName;
  };

  # Spend per month: domains bought that month, plus renewals of domains
  # bought in the same calendar month of an earlier year. Months with no
  # purchase only carry renewals, so the worst of those is checked too.
  spend =
    domains:
    let
      bought = lib.filter (r: r != null) (lib.mapAttrsToList (_: d: d.registration) domains);
      monthOf = r: lib.substring 5 2 r.month;
      inMonth =
        m:
        lib.foldl' (acc: r: acc + r.costUsd) 0 (lib.filter (r: r.month == m) bought)
        + lib.foldl' (acc: r: acc + r.renewalUsd) 0 (
          lib.filter (r: monthOf r == lib.substring 5 2 m && r.month < m) bought
        );
      renewalsOnly =
        mm: lib.foldl' (acc: r: acc + r.renewalUsd) 0 (lib.filter (r: monthOf r == mm) bought);
    in
    lib.genAttrs (map (r: r.month) bought) inMonth
    // lib.listToAttrs (
      map (mm: lib.nameValuePair "every ${mm}" (renewalsOnly mm)) (lib.unique (map monthOf bought))
    );

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

  # The domains when every month's spend fits the budget, otherwise an error
  # naming each month over it.
  budget =
    limit: domains:
    let
      over = lib.filterAttrs (_: usd: usd > limit) (spend domains);
    in
    if over == { } then
      domains
    else
      throw "Cloudflare spend over the ${toString limit} USD monthly budget:\n${
        lib.concatStrings (lib.mapAttrsToList (m: usd: "  - ${m}: ${toString usd} USD\n") over)
      }";
  infraVaults = checked "proton.infraVaults" InfraVaults;
}
