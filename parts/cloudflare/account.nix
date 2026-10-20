# Non-secret facts about the Cloudflare account. Zone IDs live with each
# domain under identity.domains.
{
  cloudflare = {
    accountId = "73f11fa58ac09529a4fb40284b8ce236";

    # R2 bucket holding the encrypted OpenTofu state. Created once by hand,
    # since the state cannot live in a bucket the state itself creates.
    stateBucket = "nix-images-tofu-state";

    # Every minted token stops working on this date. To rotate: bump it and
    # re-apply the bootstrap layer, then store the new values in Proton Pass.
    tokenExpiry = "2027-01-15T00:00:00Z";

    # Cloudflare has no spending cap of its own (budget alerts only email), so
    # this one is enforced here: the declared registrations must fit it, and
    # `registrar register` refuses a purchase that would exceed it this month.
    # About three domains a month at current prices.
    monthlyBudgetUsd = 40;
  };
}
