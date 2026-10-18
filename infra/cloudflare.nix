# Layer 2: what lives on the zone. Planned on every PR with the agent-readonly
# token, applied from master by CI with the ci-apply token.
{
  lib,
  settings,
  backend,
}:
let
  inherit (settings) zone proton;

  record =
    attrs:
    {
      zone_id = settings.zoneId;
      ttl = 1; # automatic
    }
    // attrs;

  protonRecords = lib.optionalAttrs proton.enable (
    {
      proton-verification = {
        name = zone;
        type = "TXT";
        content = "protonmail-verification=${proton.verification}";
      };
      proton-mx-1 = {
        name = zone;
        type = "MX";
        content = "mail.protonmail.ch";
        priority = 10;
      };
      proton-mx-2 = {
        name = zone;
        type = "MX";
        content = "mailsec.protonmail.ch";
        priority = 20;
      };
      proton-spf = {
        name = zone;
        type = "TXT";
        content = "v=spf1 include:_spf.protonmail.ch ~all";
      };
      proton-dmarc = {
        name = "_dmarc.${zone}";
        type = "TXT";
        content = "v=DMARC1; p=quarantine";
      };
    }
    // lib.listToAttrs (
      map
        (n: {
          name = "proton-dkim${n}";
          value = {
            name = "protonmail${n}._domainkey.${zone}";
            type = "CNAME";
            content = "protonmail${n}.domainkey.${proton.dkimId}.domains.proton.ch";
          };
        })
        [
          ""
          "2"
          "3"
        ]
    )
  );

  records = lib.mapAttrs (_: record) (protonRecords // settings.records);
in
{
  terraform = backend "cloudflare";
  provider.cloudflare = { };
}
// lib.optionalAttrs (records != { }) {
  resource.cloudflare_dns_record = records;
}
