# The shell's web target on jingzo-host (./shell.nix): its WebAssembly and
# page as static files on the loopback, reached only through the agents
# tunnel at os.<zone> behind Access (modules/hetzner/agents.nix). The same
# declarations as plain pages (./_site) are served beside it under /next/
# until they replace it, and the chat pages are passed to the chat gateway
# (modules/agents/_chat), which Access guards like the rest of this host.
{
  web,
  site,
  port,
  chat, # agents.chat: the gateway's port and where it is served
}:
{
  services.nginx = {
    enable = true;
    virtualHosts.shell-web = {
      listen = [
        {
          addr = "127.0.0.1";
          inherit port;
        }
      ];
      root = "${web}";
      locations = {
        "/next/".alias = "${site}/";
        "${chat.prefix}".proxyPass = "http://127.0.0.1:${toString chat.port}";
      };
    };
  };
}
