# The agents' chat on jingzo-host (the owner's choice, 2026-11-04: open
# source and free): a Matrix homeserver (tuwunel, Rust) and Element Web, on
# the loopback, reached only through the agents tunnel at chat.<zone>
# behind Access. One hostname carries both, Element at / and the homeserver
# at /_matrix, so the Access session covers the client's calls. Federation
# is off: the server speaks to no other.
#
#   matrix-token   once a boot, before the server: a registration token the
#                  seed alone knows (/run/matrix, never printed)
#   matrix-seed    after the server: registers the owner, the agents' bot
#                  and every team if their logins are not in the host's state vault
#                  yet, generating each password on the host and storing
#                  it as a Proton Pass login item (Kagamizo-Host-State,
#                  which the host may write). The owner signs in to Element
#                  with Proton Pass; nothing is typed by hand.
{
  zone,
  elementPort,
  matrixPort,
  owner, # the owner's Matrix localpart, from their address
  teams, # every team: each its own login (modules/agents/rooms.nix)
  passCli,
  tokenFile,
  stateVault,
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
  users = [
    owner
    "agents"
  ]
  ++ teams;
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
      allow_registration = true;
      registration_token_file = "${tokenDir}/registration-token";
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
      description = "The Matrix registration token, for this boot";
      wantedBy = [ "multi-user.target" ];
      before = [ "matrix-tuwunel.service" ];
      requiredBy = [ "matrix-tuwunel.service" ];
      path = [ pkgs.coreutils ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        RuntimeDirectory = "matrix";
        RuntimeDirectoryMode = "0750";
      };
      script = ''
        umask 027
        head -c 32 /dev/urandom | base64 -w0 | tr -d '/+=' >${tokenDir}/registration-token
        chgrp ${tuwunel.group} ${tokenDir} ${tokenDir}/registration-token
      '';
    };

    matrix-seed = {
      description = "The owner's and the agents' Matrix logins, into the host's state vault";
      wantedBy = [ "multi-user.target" ];
      after = [
        "matrix-tuwunel.service"
        "agents-secrets.service"
      ];
      requires = [ "matrix-tuwunel.service" ];
      path = [
        passCli
        pkgs.curl
        pkgs.jq
        pkgs.coreutils
      ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        Restart = "on-failure";
        RestartSec = 30;
      };
      script = ''
        set -euo pipefail
        export PROTON_PASS_KEY_PROVIDER=fs HOME=/root
        export PROTON_PASS_AGENT_REASON="jingzo-host: the Matrix logins"
        pass-cli info >/dev/null 2>&1 || pass-cli login --pat "$(cat ${tokenFile})" >/dev/null
        base=http://127.0.0.1:${toString matrixPort}
        for _ in $(seq 1 30); do curl -fsS "$base/_matrix/client/versions" >/dev/null 2>&1 && break; sleep 2; done
        have=$(pass-cli item list --vault-name ${stateVault} --output json | jq -c '[.items[].title]')
        for user in ${toString users}; do
          title="matrix-$user"
          jq -e --arg t "$title" 'index($t)' <<<"$have" >/dev/null && continue
          # The password is made here and goes two places only: the
          # homeserver and the vault. It is never printed.
          pw=$(head -c 24 /dev/urandom | base64 -w0 | tr -d '/+=')
          token=$(cat ${tokenDir}/registration-token)
          session=$(jq -n --arg u "$user" --arg p "$pw" '{username: $u, password: $p, auth: {type: "m.login.registration_token", token: "x"}, initial_device_display_name: "seed"}' |
            jq --arg t "$token" '.auth.token = $t' |
            curl -fsS -X POST "$base/_matrix/client/v3/register" -H 'Content-Type: application/json' -d @- 2>/dev/null |
            jq -r '.session // empty') || true
          # A first call without the flow's session id starts the flow; the
          # second completes it. tuwunel accepts the one-shot form above
          # when the token is right; when it answered with a session, finish.
          if [ -n "$session" ]; then
            jq -n --arg u "$user" --arg p "$pw" --arg t "$token" --arg s "$session" \
              '{username: $u, password: $p, auth: {type: "m.login.registration_token", token: $t, session: $s}}' |
              curl -fsS -X POST "$base/_matrix/client/v3/register" -H 'Content-Type: application/json' -d @- >/dev/null
          fi
          jq -n --arg t "$title" --arg u "$user" --arg p "$pw" --arg o "${origin}" --arg s "@$user:${serverName}" \
            '{title: $t, username: $u, email: null, password: $p, totp_uri: null, urls: [$o], note: ("Matrix login " + $s + ", made by jingzo-host (modules/hetzner/_chat.nix). Sign in to Element at " + $o + " with it.")}' |
            pass-cli item create login --vault-name ${stateVault} --from-template - >/dev/null
          unset pw
          echo "matrix-seed: registered $user, login stored as ${stateVault}/$title"
        done
      '';
    };
  };
}
