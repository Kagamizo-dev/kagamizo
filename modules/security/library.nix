# modules/security in the shell's library (../shell): a card on the security
# shelf for the module, and OWASP ZAP as a card on the Yoga.
{
  shell.apps = {
    security = {
      name = "Security";
      category = "security";
      kind = "module";
      module = "security";
      description = "Penetration tests of our own surfaces only: the scope, the testers and the scanners";
    };
    zap = {
      name = "OWASP ZAP";
      category = "security";
      kind = "native";
      module = "security";
      command = "zap";
      description = "Test our own web services, actively, with a screen";
      targets = [ "yoga-c940" ];
    };
  };
}
