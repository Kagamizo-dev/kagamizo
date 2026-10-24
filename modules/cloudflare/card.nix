# Cloudflare's card: the registrar budget the repo already enforces.
{ config, ... }:
{
  mercury.cards.cloudflare = {
    limitUsd = config.cloudflare.monthlyBudgetUsd;
    interval = "monthly";
    why = "domain registrations and renewals (cloudflare.monthlyBudgetUsd)";
  };
}
