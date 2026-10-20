# The OpenTofu layer: what lives on each zone, derived from identity.domains. Planned on
# every PR with the agent-readonly token, applied from master by CI with the
# ci-apply token. Domains without a zoneId yet contribute nothing.
{
  lib,
  domains,
  terraform,
}:
let
  # Resource names must be unique across zones: kagamizo.com -> kagamizo-com.
  slug = lib.replaceStrings [ "." ] [ "-" ];

  protonRecords =
    zone: proton:
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
    );

  zoneRecords =
    zone: d:
    lib.mapAttrs' (
      name: attrs:
      lib.nameValuePair "${slug zone}-${name}" (
        {
          zone_id = d.zoneId;
          ttl = 1; # automatic
        }
        // attrs
      )
    ) (lib.optionalAttrs (d.proton != null) (protonRecords zone d.proton) // d.records);

  records = lib.concatMapAttrs zoneRecords (lib.filterAttrs (_: d: d.zoneId != null) domains);
in
{
  inherit terraform;
  provider.cloudflare = { };
}
// lib.optionalAttrs (records != { }) {
  resource.cloudflare_dns_record = records;
}
