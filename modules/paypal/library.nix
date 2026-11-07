# modules/paypal in the shell's library (../shell): a service of the bank
# (../bank), shown inside the Bank card rather than as a card of its own.
{
  shell.services."paypal".app = "bank";
}
