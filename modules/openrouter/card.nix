# OpenRouter's card. It is Jingzo's (QSearch LLC's) card until Kagamizo has a
# bank account of its own: the owner's call, 2026-10-23. Its limit is the
# owner's $50 a week (2026-11-02), today enough for all the keys' caps
# (openrouter.keys: $125/month ≤ $50/week × 4 = $200/month); Lean proves
# keys_within and teams_within (modules/agents/tiers.nix).
{ lib, config, ... }:
let
  keyCaps = lib.foldl' (n: k: n + k.limitUsd) 0 (lib.attrValues config.openrouter.keys);
in
{
  # Minted by the owner on 2026-11-02 as "Research-OpenRouter" (••5055).
  mercury.cards.openrouter = {
    nickname = "Research-OpenRouter";
    limitUsd = 50;
    interval = "weekly";
    merchantLock = "OpenRouter";
    why = "OpenRouter credits, Jingzo's (the keys' caps total ${toString keyCaps})";
    account = "mercury-jingzo";
  };
}
