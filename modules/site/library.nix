# modules/site in the shell's library (../shell): the status page, a card on
# the system shelf that opens it.
{
  shell.apps.status = {
    name = "Status";
    category = "system";
    kind = "web";
    module = "site";
    description = "CI, pipelines, teams, money and records, generated from the repository";
    url = "https://status.mirazo.org";
  };
}
