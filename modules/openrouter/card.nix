# OpenRouter's card: enough for every declared key's cap, and no more. It is
# Jingzo's (QSearch LLC's) card until Kagamizo has a bank account of its own:
# the owner's call, 2026-10-23.
{ lib, config, ... }:
{
  mercury.cards.openrouter = {
    limitUsd = lib.foldl' (n: k: n + k.limitUsd) 0 (lib.attrValues config.openrouter.keys);
    interval = "monthly";
    why = "credits for the keys in openrouter.keys";
    account = "mercury-jingzo";
  };
}
