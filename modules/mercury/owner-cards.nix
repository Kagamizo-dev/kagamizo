# The Mercury cards that take over what the owner pays by their own cards
# today (accounts.held.*.payment.ownerCard.replacedBy): every payment ends on
# a Mercury virtual card of its own (the owner's rule, 2026-11-01). The owner
# mints each; `cards plan` lists the ones not minted yet. Mirazo's personal
# Mercury has no virtual cards, so the owner's own accounts are paid from
# Jingzo's, as the owner's draw.
{ config, ... }:
{
  mercury.cards = {
    proton = {
      limitUsd = 150;
      interval = "yearly";
      why = "Proton Unlimited, the owner's mail and Pass";
      account = "mercury-jingzo";
      between = {
        for = "mirazo";
        as = "draw";
      };
    };
    northwest-jingzo = {
      limitUsd = 150;
      interval = "yearly";
      why = "Northwest, Jingzo's registered agent";
      account = "mercury-jingzo";
    };
    # Minted by the owner on 2026-10-21 as "Media" (••1975), found by
    # `cards plan`'s discovery on 2026-11-03.
    netflix = {
      nickname = "Media";
      limitUsd = 20;
      interval = "monthly";
      merchantLock = "Netflix";
      why = "Netflix, the owner's own";
      account = "mercury-jingzo";
      between = {
        for = "mirazo";
        as = "draw";
      };
    };
    amazon = {
      limitUsd = 150;
      interval = "yearly";
      why = "Amazon Prime, the owner's own";
      account = "mercury-jingzo";
      between = {
        for = "mirazo";
        as = "draw";
      };
    };
    hetzner = {
      # The card's limit is Hetzner's budget, so the two never drift.
      limitUsd = config.hetzner.monthlyBudgetUsd;
      interval = "monthly";
      why = "Hetzner, Jingzo's host (hetzner.monthlyBudgetUsd)";
      account = "mercury-jingzo";
    };
  };
}
