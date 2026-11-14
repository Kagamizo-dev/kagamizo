# modules/hetzner in the shell's library (../shell): part of the base, a row
# of Settings under Infrastructure, and the cards of the services it hosts
# behind Access.
{ config, ... }:
let
  at = n: "https://${n}.${config.hetzner.host.agents.zone}";
in
{
  shell = {
    base.hetzner = {
      section = "infrastructure";
      why = "jingzo-host: the server, its installer and its always-on services";
    };
    apps = {
      agents = {
        name = "Agents";
        category = "work";
        kind = "web";
        module = "hetzner";
        description = "Open WebUI: chat with the open-weight models";
        url = at "agents";
      };
      chat = {
        name = "Chat";
        category = "chat";
        kind = "web";
        module = "hetzner";
        description = "Element: one Matrix room for each team";
        url = at "chat";
      };
    };
  };
}
