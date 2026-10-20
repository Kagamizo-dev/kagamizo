# The person at the root of every identity. Root-level secrets (the Cloudflare
# root token, the bootstrap state, the registrar token) live in this vault, and
# its Proton login carries the 2FA every one of them is gated by.
{
  identity.entities.zachariah = {
    legalName = "Zachariah";
    kind = "person";
    vault = "Zachariah-Root";
  };
}
