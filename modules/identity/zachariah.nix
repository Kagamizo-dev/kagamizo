# The person at the root of every identity. Root-level power over Cloudflare
# is never stored: it is this person's `cloudflare-login` session. This vault
# holds their own logins, behind the Proton login's 2FA.
#
# mirazo.org (مرآة mir'āh, "mirror" in Arabic, with the -zo of kagamizo and
# jingzo) is the personal domain: schooling, the PhD, research, passport and
# other personal records. Professional and consulting work goes through
# Kagamizo or QSearch. Two addresses only (the Proton plan's limit); the
# rest (academic, legal, finance, ...) are Proton Pass aliases on the domain,
# which do not count as addresses.
{
  identity = {
    entities.zachariah = {
      legalName = "Zachariah";
      kind = "person";
      vault = "Zachariah-Root";
      legal = {
        status = "natural";
        ein = "not-applicable";
      };
    };

    domains."mirazo.org" = {
      entity = "zachariah";
      zoneId = "cb57e0ebb1989ae3d67be0b64cc923ae";
      registrar = "cloudflare";
      registration = {
        month = "2026-10";
        costUsd = 8.50;
        renewalUsd = 11.20;
      };
      # From Proton's Domain names settings (it has no API for them).
      proton = {
        verification = "1439dcf0d60be363048ae4a3a198ff8a1b642477";
        dkimId = null;
      };
      mailboxes = [
        "zach" # you
        "automations" # automated mail and signups, and the catch-all
      ];
    };
  };
}
