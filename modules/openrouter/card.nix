# OpenRouter's card: enough for every declared key's cap, and no more.
{ lib, config, ... }:
{
  mercury.cards.openrouter = {
    limitUsd = lib.foldl' (n: k: n + k.limitUsd) 0 (lib.attrValues config.openrouter.keys);
    interval = "monthly";
    why = "credits for the keys in openrouter.keys";
  };
}
