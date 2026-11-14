# The shell served from the kit's machine (../kit): the Raspberry Pi serves
# the web target to the phone over the phone's tether or the same Wi-Fi, so
# the phone shows the same library with no signal at all. The web build is
# static files and holds nothing secret (the repository is public); the
# cards it opens are behind Access as everywhere else. The Pi announces
# itself over mDNS, as <hostname>.local.
{ web }:
{
  services.nginx = {
    enable = true;
    virtualHosts.kit = {
      default = true;
      root = "${web}";
    };
  };
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    publish = {
      enable = true;
      addresses = true;
    };
  };
  networking.firewall.allowedTCPPorts = [ 80 ];
}
