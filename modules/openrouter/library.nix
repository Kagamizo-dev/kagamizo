# modules/openrouter in the shell's library (../shell): part of the base, a
# row of Settings under Accounts, and the card of OpenCode, the coding agent
# it configures, on jingzo-host behind Access.
{ config, ... }:
{
  shell = {
    base.openrouter = {
      section = "accounts";
      why = "OpenRouter: models, keys, caps and routing";
    };
    apps.code = {
      name = "Code";
      category = "build";
      kind = "web";
      module = "openrouter";
      description = "OpenCode: the coding agent, in the browser";
      url = "https://code.${config.hetzner.host.agents.zone}";
    };
  };
}
