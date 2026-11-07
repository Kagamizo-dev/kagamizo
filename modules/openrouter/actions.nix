# OpenRouter's operations as governance actions, each typed by what it does
# to Jingzo's account. The management key does all of them except buying
# credit: OpenRouter's API has no purchase endpoint (its Coinbase charge is
# deprecated in favour of the web purchase flow, openapi.json read
# 2026-11-06), so `credit-topup` is declared and has no command yet: a Gap.
#
# Who may do them: accounting-jingzo writes key caps and workspace budgets
# (../governance/swarms.nix); changing a limit is first a change to
# openrouter.keys in code (the `account-limit` lifecycle), reviewed by
# accounting and legal; buying credit is the `credit-topup` lifecycle, by
# the owner's decision of 2026-11-06, bounded by the Mercury card's limit.
{
  governance.actions.openrouter = {
    plan = {
      effect = "read";
      description = "Declared keys and caps against the live ones";
      command = "openrouter plan";
    };
    usage = {
      effect = "read";
      description = "Each key's spend against its cap";
      command = "openrouter usage";
    };
    credits = {
      effect = "read";
      description = "Credit bought and used on the account";
      command = "openrouter credits";
    };
    key-limits = {
      effect = "write";
      description = "Mint missing keys and set every key's cap to its declaration";
      command = "openrouter apply";
    };
    workspace-budget = {
      effect = "write";
      description = "Set a workspace's daily, weekly, monthly or lifetime budget";
    };
    credit-topup = {
      effect = "spend";
      description = "Buy credit with the account's card (no API; a Gap)";
    };
  };
}
