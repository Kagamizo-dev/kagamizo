# DeepSeek Harness on jingzo-host (../dsh): its web UI on the loopback,
# reached through the agents tunnel at harness.<zone> behind Access. Its
# profile is the shipped `web` one under a patch rendered by the dsh
# module (../dsh/patch.nix) from the same `config.openrouter` declarations
# a headless session uses, with the host-only tier-1 provider and the
# experimental agent-team plugins added. The harness's own state (sessions,
# the plugins its agents add) lives in /var/lib/dsh; what should outlive
# the host goes to the repository as a pull request
# (modules/governance/changes.nix).
{
  zone,
  port,
  dsh,
  patch, # config.dsh.renderPatch { ... } from host.nix
  repoFullName,
  appToken, # packages.github-app-token
  teamsJson, # agents.teamsJson
}:
{ pkgs, lib, ... }:
let
  host = "harness.${zone}";
  work = "/var/lib/dsh/work";
  repo = "https://github.com/${repoFullName}.git";
in
{
  # A fixed user, so the hourly GitHub token (root:agents, 0640) is readable
  # across restarts, where a dynamic user's credentials would be copied once.
  users.users.dsh = {
    isSystemUser = true;
    group = "agents";
    home = "/var/lib/dsh";
  };
  users.groups.agents = { };

  systemd.services = {
    dsh-web = {
      description = "DeepSeek Harness, web UI";
      wantedBy = [ "multi-user.target" ];
      after = [
        "agents-secrets.service"
        "llama-cpp.service"
        "dsh-work.service"
      ];
      requires = [
        "agents-secrets.service"
        "dsh-work.service"
      ];
      path = [
        pkgs.git
        pkgs.coreutils
        pkgs.bash
      ];
      environment = {
        DSH_HOME = "/var/lib/dsh";
        HOME = "/var/lib/dsh";
        # The declared teams (../agents/teams.nix), for the agents to read.
        KAGAMIZO_TEAMS = pkgs.writeText "teams.json" teamsJson;
      };
      serviceConfig = {
        User = "dsh";
        Group = "agents";
        StateDirectory = "dsh";
        WorkingDirectory = work;
        EnvironmentFile = "/run/agents/openrouter.env";
        ExecStart = lib.concatStringsSep " " [
          (lib.getExe dsh)
          "--profile web"
          "--patch ${patch}"
          "--host 127.0.0.1"
          "--port ${toString port}"
          "--no-open"
          "--public-url https://${host}/"
          "--trusted-host ${host}"
        ];
        Restart = "on-failure";
        RestartSec = 10;
        ProtectSystem = "strict";
        ProtectHome = true;
        ReadWritePaths = [ "/var/lib/dsh" ];
        PrivateTmp = true;
        NoNewPrivileges = true;
      };
    };

    # The agents' workspace: the repository, pushing as the App through a
    # credential helper that reads the hour's token (never the key).
    dsh-work = {
      description = "The agents' checkout of the repository";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      path = [
        pkgs.git
        pkgs.coreutils
      ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "dsh";
        Group = "agents";
        StateDirectory = "dsh";
      };
      script = ''
        export HOME=/var/lib/dsh
        if [ ! -d ${work}/.git ]; then
          git clone --quiet ${repo} ${work}
        fi
        git -C ${work} config user.name "kagamizo-agents[bot]"
        git -C ${work} config user.email "agents@${zone}"
        # The token file is written by github-app-token (root:agents).
        git -C ${work} config credential.helper \
          '!f() { echo username=x-access-token; echo "password=$(cat /run/agents/github-token 2>/dev/null)"; }; f'
      '';
    };

    # The App's installation token, renewed every hour (it lives one).
    github-app-token = {
      description = "The agents' GitHub App token, for the hour";
      after = [ "agents-secrets.service" ];
      path = [ pkgs.coreutils ];
      serviceConfig = {
        Type = "oneshot";
        Environment = [
          "PROTON_PASS_KEY_PROVIDER=fs"
          "HOME=/root"
          "PROTON_PASS_AGENT_REASON=jingzo-host: the agents' GitHub token for the hour"
        ];
      };
      script = ''
        umask 027
        ${lib.getExe appToken} /run/agents/github-token.new host >/dev/null || exit 0
        chgrp agents /run/agents/github-token.new
        mv /run/agents/github-token.new /run/agents/github-token
      '';
    };
  };

  systemd.timers.github-app-token = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "3min";
      OnUnitActiveSec = "50min";
    };
  };
}
