# Mercury through OAuth, not dashboard tokens: `mercury-session login` runs
# the official `mercury login` (scopes offline_access, read, write). Each
# held Mercury account has its own session (access and refresh token), kept
# in its owner's sessions vault as MERCURY_SESSION (profile mercury-<owner>).
# Every command that talks to Mercury restores it into the CLI's own
# credentials file, lets the CLI refresh it, and stores it back, so the
# session renews itself and nothing is minted by hand.
#
#   mercury-session [--account A] login    print Mercury's approval link and
#                                          wait for it; on a machine with a
#                                          browser it opens there
#   mercury-session [--account A] status   whether the stored session works
#   mercury-session callback <address>     hand a phone's failed 127.0.0.1
#                                          page to the waiting login
#
# Approving on another device (a phone) leaves its browser on a failed
# 127.0.0.1 page: that page's address is the one-time callback. The code in
# it is useless without the PKCE verifier, which never leaves the login.
{ lib, config, ... }:
let
  top = config;
  secret = import ../_lib/secret.nix;
  accounts = lib.filterAttrs (_: a: a.provider == "mercury") config.accounts.held;
  profile = name: "mercury-${accounts.${name}.owner}";
in
{
  options.mercury.profiles = lib.mkOption {
    type = lib.types.attrsOf lib.types.str;
    readOnly = true;
    description = "Per held Mercury account: the secretspec profile holding its session.";
  };

  config = {
    mercury.profiles = lib.mapAttrs (name: _: profile name) accounts;

    secrets.profiles = lib.mapAttrs' (
      name: a:
      lib.nameValuePair (profile name) {
        defaults.providers = [ "${a.owner}-sessions" ];
        MERCURY_SESSION =
          secret "Mercury OAuth session for ${name} (refresh token), rewritten on every use" "mercury-session"
          // {
            required = false;
          };
      }
    ) accounts;

    accounts.demands = lib.mapAttrsToList (name: _: {
      account = name;
      capability = "oauthSessions";
      need = true;
      why = "mercury-session (${name}) signs in with OAuth, not dashboard tokens";
    }) accounts;

    perSystem =
      { pkgs, config, ... }:
      let
        spec = config.packages.secretspec-toml;
        # Sourced by every Mercury wrapper: a private HOME holding the CLI's
        # credentials file, restored from MERCURY_SESSION and saved back on
        # exit into MERCURY_PROFILE.
        withSession = pkgs.writeText "mercury-with-session.sh" ''
          mercury_home=$(mktemp -d)
          chmod 700 "$mercury_home"
          # pass-cli finds its session under the caller's HOME, so saving
          # runs there, not in the private one.
          caller_home=$HOME caller_config=''${XDG_CONFIG_HOME:-}
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
              HOME=$caller_home XDG_CONFIG_HOME=$caller_config secretspec set MERCURY_SESSION --file ${spec} --profile "''${MERCURY_PROFILE:?}" \
                --from-file "$creds" --reason "mercury: save the refreshed session" >/dev/null
            fi
            rm -rf "$mercury_home"
          }
          trap mercury_save EXIT
        '';

        # Resolves --account into $account and $MERCURY_PROFILE; sourced
        # with the wrapper's arguments, it leaves the rest in "$@".
        pick = pkgs.writeText "mercury-pick-account.sh" ''
          mercury_accounts=(${lib.concatStringsSep " " (lib.attrNames accounts)})
          account=
          if [ "''${1:-}" = --account ]; then
            account=''${2:?name the account: ''${mercury_accounts[*]}}
            shift 2
          fi
          if [ -z "$account" ]; then
            [ ''${#mercury_accounts[@]} -eq 1 ] || { echo "name the account: --account ''${mercury_accounts[*]}" >&2; exit 2; }
            account=''${mercury_accounts[0]}
          fi
          case " ''${mercury_accounts[*]} " in
            *" $account "*) ;;
            *) echo "no Mercury account $account; declared: ''${mercury_accounts[*]}" >&2; exit 2 ;;
          esac
          MERCURY_PROFILE=$(jq -r --arg a "$account" '.[$a]' <<<${lib.escapeShellArg (builtins.toJSON top.mercury.profiles)})
          export MERCURY_PROFILE
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
                echo "mercury-session: signed in; session stored under profile $MERCURY_PROFILE" >&2
                ;;
              status)
                mercury status >&2
                mercury org get --format json >/dev/null && echo "mercury-session: the session works" >&2
                ;;
            esac
          '';
        };
      in
      {
        packages = {
          mercury-with-session = withSession;
          mercury-pick-account = pick;

          mercury-session = pkgs.writeShellApplication {
            name = "mercury-session";
            runtimeInputs = [
              config.packages.secretspec
              config.packages.pass-cli
              config.packages.governance-authorize
              pkgs.curl
              pkgs.jq
            ];
            text = builtins.seq top.accounts.checked ''
              export PROTON_PASS_KEY_PROVIDER=''${PROTON_PASS_KEY_PROVIDER:-fs}
              usage="usage: mercury-session [--account A] <login|status> | callback <address>"
              if [ "''${1:-}" = callback ]; then
                # Hand the phone's failed 127.0.0.1 page to the login waiting here.
                address=''${2:?$usage}
                case "$address" in
                  http://127.0.0.1:*/callback\?*) ;;
                  *) echo "mercury-session: not a 127.0.0.1 callback address" >&2; exit 2 ;;
                esac
                curl -fsS -o /dev/null "$address" && echo "mercury-session: delivered" >&2
                exit
              fi
              account= # set by the sourced picker
              # shellcheck source=/dev/null
              . ${pick}
              case "''${1:-}" in
                login | status) governance-authorize "mercury:$1" "$account" ;;
                *) echo "$usage" >&2; exit 2 ;;
              esac
              exec secretspec run --file ${spec} --profile "$MERCURY_PROFILE" \
                --reason "mercury-session $1 ($account)" -- ${run}/bin/mercury-session-run "$@"
            '';
          };
        };
      };
  };
}
