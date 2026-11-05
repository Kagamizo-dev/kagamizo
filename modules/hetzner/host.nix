# Jingzo's host on Hetzner Cloud, declared whole: the one machine with a
# fixed address, where calls that need an allow-listed IP (Mercury's
# write-scoped token) run. The cloud session only declares and applies; the
# host builds itself from this repository.
#
#   nixosConfigurations.jingzo-host            the system: its disk (disko),
#                                              network, and the timer that
#                                              pulls and switches to its
#                                              declared configuration
#   nixosConfigurations.jingzo-host-installer  a NixOS kexec image that
#                                              partitions the disk as declared
#                                              and installs jingzo-host, then
#                                              reboots into it
#   packages.jingzo-host-installer             that image's tarball, with a
#                                              static kexec from the pinned
#                                              nixpkgs (Hetzner's Ubuntu has
#                                              none); its hash is what the
#                                              first boot checks (./infra.nix)
#
# No SSH server and no remote access, as for every image in the repo: the
# host changes when the repository does.
{
  lib,
  config,
  inputs,
  withSystem,
  ...
}:
let
  inherit (lib) mkOption types;
  top = config;
  cfg = config.hetzner.host;
  # The migration's staging and exports on the host (../migration/_host.nix),
  # with the host's own build of the runner and its tools.
  staging = withSystem "x86_64-linux" (
    { config, ... }:
    import ../migration/_host.nix {
      # The host's runner: its own vault and profile (../migration/export.nix).
      migrate = config.packages.migrate-host;
      inherit (config.packages) secretspec;
      secretspecToml = config.packages.secretspec-toml;
      passCli = config.packages.pass-cli;
    }
  );

  # Tier 1: the small model on the CPU (../agents/tiers.nix).
  tier1 = import ./_tier1.nix {
    name = config.agents.tiers.small.model;
    model = config.agents.models.${config.agents.tiers.small.model};
    port = cfg.agents.tier1Port;
  };

  # The agents' chat: Matrix and Element, behind the same tunnel (./_chat.nix).
  chat = withSystem "x86_64-linux" (
    { config, ... }:
    let
      svc = lib.findFirst (
        s: s.name == "chat"
      ) (throw "hetzner.host.agents: no chat service") cfg.agents.services;
    in
    import ./_chat.nix {
      inherit (cfg.agents) zone;
      elementPort = svc.port;
      matrixPort = (lib.head svc.paths).port;
      owner = lib.head (lib.splitString "@" (lib.head cfg.agents.viewers));
      passCli = config.packages.pass-cli;
      tokenFile = "/var/lib/kagamizo/host-token";
      stateVault = top.proton.infraVaults.hostState;
    }
  );

  # DeepSeek Harness's web UI (../dsh, ./_harness.nix).
  harness = withSystem "x86_64-linux" (
    { config, ... }:
    let
      model = id: {
        inherit id;
        name = id;
      };
      patch = config.dsh.renderPatch {
        providers = {
          openrouter = {
            displayName = "OpenRouter (Jingzo's capped key)";
            api = "openai-completions";
            baseURL = "https://openrouter.ai/api/v1";
            apiKeyEnv = "OPENROUTER_API_KEY";
            models = map model top.openrouter.models;
            compat.thinkingFormat = "openrouter";
          };
          host = {
            displayName = "jingzo-host tier 1 (free)";
            api = "openai-completions";
            baseURL = "http://127.0.0.1:${toString cfg.agents.tier1Port}/v1";
            apiKey = "local";
            models = [ (model top.agents.tiers.small.model) ];
            defaultContextWindow = 8192;
            defaultMaxTokens = 2048;
          };
        };
        inherit (top.openrouter) defaultModel;
        workspaceRoot = "/var/lib/dsh/work";
        extra = [
          # Agent teams (experimental): the plan's teams, added to the profile.
          {
            insert = [
              {
                id = "agent-team";
                name = "@deepseek-ai/dsh-experimental-agent-team";
              }
              {
                id = "agent-team-profile";
                name = "@deepseek-ai/dsh-experimental-agent-team-profile";
              }
              {
                id = "tool-agent-team";
                name = "@deepseek-ai/dsh-experimental-tool-agent-team";
              }
              {
                id = "ui-agent-team";
                name = "@deepseek-ai/dsh-experimental-client-ui-agent-team";
              }
            ];
          }
        ];
      };
    in
    import ./_harness.nix {
      inherit (cfg.agents) zone;
      inherit
        (lib.findFirst (
          s: s.name == "harness"
        ) (throw "hetzner.host.agents: no harness service") cfg.agents.services)
        port
        ;
      dsh = config.packages.dsh;
      inherit patch;
      repoFullName = "${top.github.org}/kagamizo";
      appToken = config.packages.github-app-token;
      inherit (top.agents) teamsJson;
    }
  );

  # The end of GitHub's App manifest flow (../github/agents-app.nix).
  githubApp = withSystem "x86_64-linux" (
    { config, ... }:
    let
      svc = lib.findFirst (
        s: s.name == "chat"
      ) (throw "hetzner.host.agents: no chat service") cfg.agents.services;
    in
    import ./_github-app.nix {
      inherit (lib.findFirst (p: p.path == "^/_github/") (throw "no _github path") svc.paths) port;
      inherit (top.github.agentsApp) item;
      stateVault = top.proton.infraVaults.hostState;
      passCli = config.packages.pass-cli;
      tokenFile = "/var/lib/kagamizo/host-token";
    }
  );

  # Open WebUI and OpenCode, behind the agents tunnel (./agents.nix).
  agents = withSystem "x86_64-linux" (
    { config, ... }:
    import ./_agents.nix {
      inherit (cfg.agents) services zone tier1Port;
      inherit (config.packages) secretspec;
      secretspecToml = config.packages.secretspec-toml;
      passCli = config.packages.pass-cli;
      opencodeConfig = config.packages.opencode-config;
      tokenFile = "/var/lib/kagamizo/host-token";
      stateVault = top.proton.infraVaults.hostState;
      # The Android SDK's packages (../android) and, when the owner enables
      # it, Steam's (../gamedev), unfree in nixpkgs.
      alsoUnfree = top.android.unfreeNames ++ top.gamedev.unfreeNames;
    }
  );

  # The share-from-phone relay, Discord into the Matrix room (../discord).
  discord = withSystem "x86_64-linux" (
    { config, ... }:
    let
      svc = lib.findFirst (
        s: s.name == "chat"
      ) (throw "hetzner.host.agents: no chat service") cfg.agents.services;
    in
    import ../discord/_host.nix {
      relay = config.packages.discord-relay;
      inherit (top.discord) channelId ownerUserId;
      matrixPort = (lib.head svc.paths).port;
      inherit (cfg.agents) zone;
      room = top.discord.matrixRoom;
      owner = lib.head (lib.splitString "@" (lib.head cfg.agents.viewers));
    }
  );

  # The media pipeline: the indexer and the renderer (../media/_host.nix).
  media = withSystem "x86_64-linux" (
    { config, ... }:
    import ../media/_host.nix {
      mediaIndex = config.packages.media-index;
      mediaRender = config.packages.media-render;
      inherit (top.media)
        whisperModel
        incoming
        catalog
        cuts
        renders
        ;
    }
  );

  # The phone's twin, the declared Android emulator (../android/_host.nix).
  androidTwin = withSystem "x86_64-linux" (
    { config, ... }:
    import ../android/_host.nix {
      twin = config.packages.android-twin;
      screen = config.packages.android-twin-screen;
    }
  );

  # The brokerage's nightly ledger, only while money.ledger.enable is
  # (../money/_host.nix).
  money = withSystem "x86_64-linux" (
    { config, ... }:
    import ../money/_host.nix {
      inherit (top.money.ledger)
        enable
        dir
        at
        agent
        ;
      inherit (config.packages) ledger;
      passCli = config.packages.pass-cli;
    }
  );

  # Steam's tools, only while gamedev.steam.enable is (../gamedev/_host.nix).
  gamedev = import ../gamedev/_host.nix { inherit (top.gamedev.steam) enable; };

  # The disk Hetzner Cloud gives an x86 server (virtio-scsi, /dev/sda),
  # GPT with a BIOS boot partition and an ESP, so GRUB boots either way.
  disk = {
    disko.devices.disk.main = {
      type = "disk";
      device = "/dev/sda";
      content = {
        type = "gpt";
        partitions = {
          bios = {
            size = "1M";
            type = "EF02";
          };
          esp = {
            size = "512M";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
            };
          };
          root = {
            size = "100%";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/";
            };
          };
        };
      };
    };
  };

  host =
    { pkgs, modulesPath, ... }:
    {
      imports = [
        (modulesPath + "/profiles/qemu-guest.nix")
        inputs.disko.nixosModules.disko
        disk
        staging
        tier1
        agents
        chat
        discord
        githubApp
        harness
        media
        androidTwin
        gamedev
        money
      ];
      networking.hostName = cfg.name;
      boot.loader.grub = {
        efiSupport = true;
        efiInstallAsRemovable = true;
      };
      # Hetzner Cloud hands the IPv4 out by DHCP.
      networking.useNetworkd = true;
      services = {
        # DHCP's DNS servers, through resolved (networkd hands them over).
        resolved.enable = true;
        openssh.enable = false;
        # No SSH, so the console is how the host shows its state: getty
        # keeps the boot messages, and host-report prints the state over
        # them, for host-console's screenshot (./console.nix).
        getty.extraArgs = [ "--noclear" ];
      };
      systemd = {
        network.networks."10-uplink" = {
          matchConfig.Name = "en*";
          networkConfig.DHCP = "ipv4";
        };
        services.host-report = {
          description = "Print the host's state on its console";
          wantedBy = [ "multi-user.target" ];
          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];
          path = [
            pkgs.iproute2
            pkgs.systemd
            pkgs.coreutils
            pkgs.gnugrep
          ];
          serviceConfig = {
            Type = "oneshot";
            # The journal (host-rescue reads it) and the console.
            StandardOutput = "journal+console";
          };
          script = ''
            # Long enough for migration-staging's first tries.
            sleep 120
            echo "== host-report $(date -u +%FT%TZ)"
            ip -4 -brief addr
            resolvectl dns 2>/dev/null | grep -v '^Global' || true
            echo "-- failed units"; systemctl --failed --no-legend --plain || true
            [ -r /var/lib/kagamizo/host-token ] && echo "-- host token: present" || echo "-- host token: MISSING"
            echo "-- migration-staging"; journalctl -u migration-staging -b --no-pager -n 12 -o cat || true
          '';
        };
      };
      nix.settings = {
        experimental-features = [
          "nix-command"
          "flakes"
        ];
        # What CI built (../cache): the host downloads its system rather than
        # building it. On 2026-11-04 building Open WebUI (unfree, so not in
        # cache.nixos.org) here ran the 8 GB host out of memory.
        extra-substituters = [ "https://${config.cache.host}" ];
        extra-trusted-public-keys = [ config.cache.publicKey ];
        # Whatever is still built here, one at a time on two cores.
        max-jobs = 1;
        cores = 2;
      };
      # Room for a build or a spike: compressed RAM first, then a swap file.
      zramSwap.enable = true;
      swapDevices = [
        {
          device = "/var/lib/swapfile";
          size = 8 * 1024;
        }
      ];
      # The host follows the repository: on a timer it builds its declared
      # configuration and switches to it.
      system.autoUpgrade = {
        enable = true;
        flake = "${cfg.flake}#${cfg.name}";
        dates = cfg.upgradeAt;
        allowReboot = true;
      };
      environment.systemPackages = [ pkgs.git ];
      system.stateVersion = "26.05";
    };

  installer =
    { pkgs, modulesPath, ... }:
    let
      target = config.flake.nixosConfigurations.${cfg.name}.config;
    in
    {
      imports = [ (modulesPath + "/installer/netboot/netboot-minimal.nix") ];
      networking.hostName = "${cfg.name}-installer";
      # The declared disk is ext4 and vfat: no ZFS in the image.
      boot.supportedFilesystems.zfs = lib.mkForce false;
      nix.settings.experimental-features = [
        "nix-command"
        "flakes"
      ];
      # Partition as declared, install the declared system, reboot into it.
      systemd.services.install-host = {
        wantedBy = [ "multi-user.target" ];
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        path = [
          pkgs.nix
          pkgs.nixos-install-tools
          pkgs.git
          pkgs.util-linux
        ];
        serviceConfig = {
          Type = "oneshot";
          StandardOutput = "journal+console";
        };
        script = ''
          ${target.system.build.diskoScript}
          nixos-install --no-root-passwd --flake ${lib.escapeShellArg "${cfg.flake}#${cfg.name}"}
          systemctl reboot
        '';
      };
      system.stateVersion = "26.05";
    };
in
{
  options.hetzner.host = {
    name = mkOption {
      type = types.strMatching "[a-z][a-z0-9-]*";
      default = "jingzo-host";
    };
    flake = mkOption {
      type = types.strMatching "github:[A-Za-z0-9-]+/[A-Za-z0-9._-]+(/[A-Za-z0-9._/-]+)?";
      description = "The flake the host installs from and follows (a public GitHub ref).";
    };
    upgradeAt = mkOption {
      type = types.str;
      default = "*-*-* 04:40:00";
      description = "When the host pulls and switches (systemd calendar).";
    };
  };

  config = {
    hetzner.host.flake = "github:Kagamizo-dev/kagamizo/ccr-a3dc11d9-lh43d5";

    flake.nixosConfigurations = {
      ${cfg.name} = inputs.nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [ host ];
      };
      "${cfg.name}-installer" = inputs.nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [ installer ];
      };
    };

    perSystem =
      { pkgs, ... }:
      let
        built = config.flake.nixosConfigurations."${cfg.name}-installer".config.system.build;
      in
      {
        packages.jingzo-host-installer = pkgs.runCommand "jingzo-host-installer.tar" { } ''
          mkdir tree
          cp -L ${built.kexecTree}/* tree/
          cp ${pkgs.pkgsStatic.kexec-tools}/bin/kexec tree/kexec
          sed -i 's|^if ! kexec -v|PATH="$(dirname "$0"):$PATH"; if ! kexec -v|' tree/kexec-boot
          tar -C tree -cf $out .
        '';
        checks.jingzo-host = config.flake.nixosConfigurations.${cfg.name}.config.system.build.toplevel;
      };
  };
}
