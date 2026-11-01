# Cloudflare's card: the registrar budget the repo already enforces.
{ config, ... }:
{
  mercury.cards.cloudflare = {
    limitUsd = config.cloudflare.monthlyBudgetUsd;
    interval = "monthly";
    why = "domain registrations and renewals (cloudflare.monthlyBudgetUsd)";
    account = "mercury-jingzo";
    # The Cloudflare account is the owner's; Jingzo paying it is their draw.
    between = {
      for = "mirazo";
      as = "draw";
    };
  };
}
