# What the units of work make, where the owner can open it: every artifact a
# unit publishes (an image, a model, a drawing, a document) is a file under
# its unit's own directory, served read-only on the loopback and reached only
# through the agents tunnel at files.<zone> behind Access
# (modules/hetzner/agents.nix). A unit writes its directory once; nginx
# serves what is there and lists it, and runs nothing.
{ port, root }:
{
  systemd.tmpfiles.rules = [ "d ${root} 0755 root root -" ];
  services.nginx = {
    enable = true;
    virtualHosts.unit-files = {
      listen = [
        {
          addr = "127.0.0.1";
          inherit port;
        }
      ];
      inherit root;
      locations."/".extraConfig = ''
        autoindex on;
        add_header X-Content-Type-Options nosniff;
        add_header Content-Security-Policy "default-src 'none'; img-src 'self'; style-src 'unsafe-inline'";
        limit_except GET HEAD { deny all; }
      '';
    };
  };
}
