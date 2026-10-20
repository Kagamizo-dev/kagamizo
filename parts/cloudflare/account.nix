# Non-secret facts about the Cloudflare account. Zone IDs live with each
# domain under identity.domains.
{
  cloudflare = {
    accountId = "73f11fa58ac09529a4fb40284b8ce236";

    # Every minted token stops working on this date. Bump it and run
    # `bootstrap apply` to extend them all in place.
    tokenExpiry = "2027-01-15T00:00:00Z";

    # Cloudflare has no spending cap of its own (budget alerts only email), so
    # this one is enforced here: the declared registrations must fit it, and
    # `registrar register` refuses a purchase that would exceed it this month.
    # About three domains a month at current prices.
    monthlyBudgetUsd = 40;
  };
}
