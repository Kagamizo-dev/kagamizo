# modules/dsh in the shell's library (../shell): DeepSeek Harness's web UI,
# on jingzo-host behind Access.
{ config, ... }:
{
  shell.apps.harness = {
    name = "Harness";
    category = "work";
    kind = "web";
    module = "dsh";
    description = "DeepSeek Harness: the agents' own workbench, which they extend";
    url = "https://harness.${config.hetzner.host.agents.zone}";
  };
}
