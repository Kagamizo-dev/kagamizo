# OpenRouter's card. It is Jingzo's (QSearch LLC's) card until Kagamizo has a
# bank account of its own: the owner's call, 2026-10-23. Its limit is the
# owner's $5 a month (2026-10-24), the first top-up; the keys' caps
# (openrouter.keys) add up to more, and the limit rises to their sum only
# when the owner says so and the keys are live.
{ lib, config, ... }:
let
  keyCaps = lib.foldl' (n: k: n + k.limitUsd) 0 (lib.attrValues config.openrouter.keys);
in
{
  mercury.cards.openrouter = {
    limitUsd = 5;
    interval = "monthly";
    why = "OpenRouter credits, the first top-up (the keys' caps total ${toString keyCaps})";
    account = "mercury-jingzo";
  };
}
