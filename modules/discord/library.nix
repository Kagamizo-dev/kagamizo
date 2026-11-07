# modules/discord in the shell's library (../shell): a card on the chat shelf,
# opening the module's page.
{
  shell.apps."discord" = {
    name = "Discord relay";
    category = "chat";
    kind = "module";
    module = "discord";
    description = "Shares from the phone, relayed into Matrix";
  };
}
