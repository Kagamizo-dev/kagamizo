# The Mercury cards that take over what the owner pays by their own cards
# today (accounts.held.*.payment.ownerCard.replacedBy): every payment ends on
# a Mercury virtual card of its own (the owner's rule, 2026-11-01). The owner
# mints each; `cards plan` lists the ones not minted yet. Mirazo's personal
# Mercury has no virtual cards, so the owner's own accounts are paid from
# Jingzo's, as the owner's draw.
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
    hetzner = {
      limitUsd = 7;
      interval = "monthly";
      why = "Hetzner, Jingzo's host (hetzner.monthlyBudgetUsd)";
      account = "mercury-jingzo";
    };
  };
}
