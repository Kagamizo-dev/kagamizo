# Hetzner's card: the owner's $5 a month (2026-10-24) for the host and its
# fixed address, on Jingzo's Mercury account like the account itself.
{ config, ... }:
{
  mercury.cards.hetzner = {
    limitUsd = config.hetzner.monthlyBudgetUsd;
    interval = "monthly";
    why = "the declared host and its primary IPv4 (hetzner.monthlyBudgetUsd)";
    account = "mercury-jingzo";
  };
}
