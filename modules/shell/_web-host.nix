# The shell's web target on jingzo-host (./shell.nix): its WebAssembly and
# page as static files on the loopback, reached only through the agents
# tunnel at os.<zone> behind Access (modules/hetzner/agents.nix).
{ web, port }:
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
    };
  };
}
