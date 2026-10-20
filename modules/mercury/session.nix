# Mercury through OAuth, not dashboard tokens: `mercury-session login` runs
# the official `mercury login` (scopes offline_access, read, write), and the
# session it makes (access and refresh token) lives in Kagamizo's vault as
# MERCURY_SESSION. Every command that talks to Mercury restores it into the
# CLI's own credentials file, lets the CLI refresh it, and stores it back,
# so the session renews itself and nothing is minted by hand.
#
#   mercury-session login    print Mercury's approval link and wait for it;
#                            on a machine with a browser it opens there
#   mercury-session status   whether the stored session still works
#
# Approving on another device (a phone) leaves its browser on a failed
# 127.0.0.1 page: that page's address is the one-time callback, delivered to
# the waiting login with `mercury-session callback <address>`. The code in it
# is useless without the PKCE verifier, which never leaves the login.
{ config, ... }:
let
  top = config;
  secret = import ../_lib/secret.nix;
in
{
  secrets.profiles.mercury-session = {
    defaults.providers = [ "kagamizo" ];
    MERCURY_SESSION =
      secret "Mercury OAuth session (refresh token), rewritten on every use" "mercury-session"
      // {
        required = false;
      };
  };

  perSystem =
    { pkgs, config, ... }:
    let
      spec = config.packages.secretspec-toml;
      # Sourced by every Mercury wrapper: a private HOME holding the CLI's
      # credentials file, restored from MERCURY_SESSION and saved back on exit.
      withSession = pkgs.writeText "mercury-with-session.sh" ''
        mercury_home=$(mktemp -d)
        chmod 700 "$mercury_home"
        export HOME=$mercury_home XDG_CONFIG_HOME=$mercury_home/.config DBUS_SESSION_BUS_ADDRESS=disabled:
        mkdir -p "$XDG_CONFIG_HOME/mercury"
        creds=$XDG_CONFIG_HOME/mercury/credentials.json
        if [ -n "''${MERCURY_SESSION:-}" ]; then
          printf %s "$MERCURY_SESSION" >"$creds"
          chmod 600 "$creds"
        fi
        unset MERCURY_SESSION
        mercury_save() {
          if [ -s "$creds" ]; then
            secretspec set MERCURY_SESSION --file ${spec} --profile mercury-session \
              --from-file "$creds" --reason "mercury: save the refreshed session" >/dev/null
          fi
          rm -rf "$mercury_home"
        }
        trap mercury_save EXIT
      '';

      run = pkgs.writeShellApplication {
        name = "mercury-session-run";
        runtimeInputs = [
          config.packages.mercury
          config.packages.secretspec
          config.packages.pass-cli
          pkgs.curl
          pkgs.coreutils
        ];
        text = ''
          # shellcheck source=/dev/null
          . ${withSession}
          creds=$XDG_CONFIG_HOME/mercury/credentials.json
          case "''${1:-}" in
            login)
              rm -f "$creds"
              # The URL goes to stderr, where the caller (or you) can read it.
              mercury login >&2
              [ -s "$creds" ] || { echo "mercury-session: no session was saved" >&2; exit 1; }
              echo "mercury-session: signed in; session stored in Kagamizo-LLC/mercury-session" >&2
              ;;
            status)
              mercury status >&2
              mercury org get --format json >/dev/null && echo "mercury-session: the session works" >&2
              ;;
            *)
              echo "usage: mercury-session <login|status|callback <address>>" >&2
              exit 2
              ;;
          esac
        '';
      };
    in
    {
      packages.mercury-with-session = withSession;

      packages.mercury-session = pkgs.writeShellApplication {
        name = "mercury-session";
        runtimeInputs = [
          config.packages.secretspec
          config.packages.pass-cli
          pkgs.curl
        ];
        text = builtins.seq top.accounts.checked ''
          export PROTON_PASS_KEY_PROVIDER=''${PROTON_PASS_KEY_PROVIDER:-fs}
          if [ "''${1:-}" = callback ]; then
            # Hand the phone's failed 127.0.0.1 page to the login waiting here.
            address=''${2:?usage: mercury-session callback <address>}
            case "$address" in
              http://127.0.0.1:*/callback\?*) ;;
              *) echo "mercury-session: not a 127.0.0.1 callback address" >&2; exit 2 ;;
            esac
            curl -fsS -o /dev/null "$address" && echo "mercury-session: delivered" >&2
            exit
          fi
          exec secretspec run --file ${config.packages.secretspec-toml} --profile mercury-session \
            --reason "mercury-session $*" -- ${run}/bin/mercury-session-run "$@"
        '';
      };
    };
}
