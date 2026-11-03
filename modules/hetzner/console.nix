# jingzo-host's console, read from CI: the host has no SSH, so its screen is
# how it shows what happened (host-report prints its state there,
# ./host.nix). `host-console` asks Hetzner's API for the console
# (request_console) and saves one screenshot through VNC (./_console.py).
#
#   nix run .#host-console -- OUT.png
#       with pass-cli signed in on the host-install agent: Hetzner's token is
#       read from Kagamizo-Install/hetzner-console (./credentials.nix), into
#       the environment only.
#
# .github/workflows/host-console.yml runs it when
# .github/host-console.request changes and keeps the PNG as an artifact.
{ config, ... }:
let
  vault = config.proton.infraVaults.install;
  inherit (config.hetzner.host) name;
in
{
  perSystem =
    { pkgs, config, ... }:
    let
      python = pkgs.python3.withPackages (p: [
        p.websockets
        p.pycryptodome
        p.pillow
      ]);
    in
    {
      packages.host-console = pkgs.writeShellApplication {
        name = "host-console";
        runtimeInputs = [
          python
          config.packages.pass-cli
          pkgs.coreutils
        ];
        text = ''
          out=''${1:?usage: host-console OUT.png}
          export PROTON_PASS_KEY_PROVIDER=''${PROTON_PASS_KEY_PROVIDER:-fs}
          HCLOUD_TOKEN=$(PROTON_PASS_AGENT_REASON="host-console: request ${name}'s console" \
            pass-cli item view --vault-name ${vault} --item-title hetzner-console --field Secret)
          [ -n "$HCLOUD_TOKEN" ] || { echo "host-console: no hetzner-console in ${vault}; run host-credentials sync" >&2; exit 1; }
          export HCLOUD_TOKEN
          exec python3 -I ${./_console.py} ${name} "$out"
        '';
      };
    };
}
