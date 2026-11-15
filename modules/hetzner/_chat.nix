# The agents' chat on jingzo-host (the owner's choice, 2026-11-04: open
# source and free): a Matrix homeserver (tuwunel, Rust) and Element Web, on
# the loopback, reached only through the agents tunnel at chat.<zone>
# behind Access. One hostname carries both, Element at / and the homeserver
# at /_matrix, so the Access session covers the client's calls. Federation
# is off: the server speaks to no other.
#
#   matrix-token   once a boot, before the server: the application
#                  service's two tokens, made here and kept only in
#                  /run/matrix (never printed, never stored), and its
#                  registration, whose namespace is exactly the declared
#                  accounts and room aliases (modules/agents/_rooms)
#   matrix-rooms   after the server: every declared room exists, with its
#                  topic, holding the owner and its team. It fails,
#                  changing nothing more, if a room holds someone not
#                  declared.
#
# There is no password and no sign-in on this homeserver (the owner's
# rule, 2026-11-15): registration is closed, every account is reached
# through the application service's token, and the owner talks through
# the shell's own page behind Access. Element is served but has nothing
# to sign in with.
{
  zone,
  elementPort,
  matrixPort,
  roomsTool, # matrix-rooms, with the declared rooms compiled in
}:
{ pkgs, config, ... }:
let
  serverName = zone;
  origin = "https://chat.${zone}";
  element = pkgs.element-web.override {
    conf = {
      default_server_config."m.homeserver" = {
        base_url = origin;
        server_name = serverName;
      };
      disable_custom_urls = true;
      disable_guests = true;
      disable_3pid_login = true;
      brand = "Kagamizo";
      default_theme = "dark";
      show_labs_settings = false;
    };
  };
  tuwunel = config.services.matrix-tuwunel;
  tokenDir = "/run/matrix";
in
{
  services.matrix-tuwunel = {
    enable = true;
    settings.global = {
      server_name = serverName;
      address = [ "127.0.0.1" ];
      port = [ matrixPort ];
      allow_federation = false;
      trusted_servers = [ ];
      allow_registration = false;
      appservice_dir = "${tokenDir}/appservices";
      allow_guest_registration = false;
      url_preview_domain_contains_allowlist = [ ];
      allow_public_room_directory_over_federation = false;
      new_user_displayname_suffix = "";
    };
  };

  # Element is a directory of links into its unwrapped build plus its own
  # config; static-web-server refuses any file that resolves outside its
  # root, so it served only config.json and the page stayed blank
  # (2026-11-06). nginx follows the links.
  services.nginx = {
    enable = true;
    virtualHosts.element = {
      listen = [
        {
          addr = "127.0.0.1";
          port = elementPort;
        }
      ];
      root = "${element}";
    };
  };

  systemd.services = {
    matrix-token = {
      description = "The Matrix application service's tokens and registration, for this boot";
      wantedBy = [ "multi-user.target" ];
      before = [ "matrix-tuwunel.service" ];
      requiredBy = [ "matrix-tuwunel.service" ];
      path = [
        pkgs.coreutils
        roomsTool
      ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        RuntimeDirectory = "matrix";
        RuntimeDirectoryMode = "0750";
      };
      script = ''
        umask 077
        for t in as-token hs-token; do
          head -c 32 /dev/urandom | base64 -w0 | tr -d '/+=' >${tokenDir}/$t
        done
        mkdir -p ${tokenDir}/appservices
        matrix-rooms registration ${tokenDir}/appservices/kagamizo.yaml ${tokenDir}/as-token ${tokenDir}/hs-token
        chgrp -R ${tuwunel.group} ${tokenDir}/appservices
        chgrp ${tuwunel.group} ${tokenDir}
        chmod 0750 ${tokenDir}/appservices
        chmod 0640 ${tokenDir}/appservices/kagamizo.yaml
      '';
    };

    matrix-rooms = {
      description = "The teams' rooms, as declared";
      wantedBy = [ "multi-user.target" ];
      after = [ "matrix-tuwunel.service" ];
      requires = [ "matrix-tuwunel.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        Restart = "on-failure";
        RestartSec = 30;
        ExecStart = "${roomsTool}/bin/matrix-rooms apply http://127.0.0.1:${toString matrixPort} ${tokenDir}/as-token";
      };
    };
  };
}
