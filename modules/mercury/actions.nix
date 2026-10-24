# Mercury's operations as governance actions: what each `cards` and
# `mercury-session` command does to the account the cards draw on.
{
  governance.actions.mercury = {
    cards-plan = {
      effect = "read";
      description = "Declared cards against the live ones";
      command = "cards plan";
    };
    cards-spend = {
      effect = "read";
      description = "Each card's spend against its limit";
      command = "cards spend";
    };
    cards-funds = {
      effect = "read";
      description = "The balances the cards draw from";
      command = "cards funds";
    };
    # Issuing a card or raising a limit lets money leave.
    cards-apply = {
      effect = "spend";
      description = "Issue missing cards, correct limits";
      command = "cards apply";
    };
    cards-prune = {
      effect = "destroy";
      description = "Cancel cards no longer declared";
      command = "cards apply --prune";
    };
    cards-freeze = {
      effect = "write";
      description = "Stop a card at once";
      command = "cards freeze";
    };
    cards-unfreeze = {
      effect = "spend";
      description = "Let a frozen card spend again";
      command = "cards unfreeze";
    };
    login = {
      effect = "session";
      description = "Sign in with Mercury's OAuth";
      command = "mercury-session login";
    };
    status = {
      effect = "read";
      description = "Whether the stored session works";
      command = "mercury-session status";
    };
  };
}
