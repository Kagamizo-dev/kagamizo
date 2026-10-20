# The person at the root of every identity. Root-level power over Cloudflare
# is never stored: it is this person's `cloudflare-login` session. This vault
# holds their own logins, behind the Proton login's 2FA.
{
  identity.entities.zachariah = {
    legalName = "Zachariah";
    kind = "person";
    vault = "Zachariah-Root";
  };
}
