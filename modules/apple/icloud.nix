# iCloud, read for the migration (modules/migration): signing in, and what
# the account holds, through the pinned pyicloud.
#
#   nix run .#icloud -- login
#       signs apple-mirazo in with its Proton Pass login (the password is
#       piped from pass-cli, never printed); Apple sends a code to the
#       owner's devices, which the session relays into the FIFO this prints.
#       The trusted session is kept in the owner's Sessions vault.
#   nix run .#icloud -- inventory OUT.json
#       what the account holds: storage by kind, photos, contacts,
#       calendars, notes, reminder lists, iCloud Drive's top level and every
#       Hide My Email relay (the logins that must move first); counts on
#       stdout, the rest in OUT.json, which stays with the owner.
{ lib, config, ... }:
let
  top = config;
  account = config.accounts.held.apple-mirazo;
  vault = config.identity.checked.entities.${account.owner}.vault;
  profile = "icloud";
in
{
  secrets.profiles.${profile} = {
    defaults.providers = [ "${account.owner}-sessions" ];
    # IMAP, CardDAV and CalDAV for the migration (imapsync, vdirsyncer):
    # an app-specific password the owner makes in Apple's account settings
    # and pastes into the prepared API-credential item.
    ICLOUD_APP_PASSWORD =
      (import ../_lib/secret.nix) {
        kind = "api-token";
        issuer = "human:console-credential";
        description = "apple-mirazo's app-specific password for IMAP, CardDAV and CalDAV";
        item = "icloud-app-password";
        template = "api-credential";
        field = "Secret";
      }
      // {
        providers = [ "${account.owner}-logins" ];
        required = false;
      };
    ICLOUD_SESSION =
      (import ../_lib/secret.nix) {
        kind = "oauth-session";
        issuer = "automation:icloud";
        needs = [ "approve-sign-in" ];
        description = "apple-mirazo's trusted iCloud session (pyicloud's cookies), base64";
        item = "icloud-session";
      }
      // {
        required = false;
      };
  };

  governance.actions.apple = {
    sign-in = {
      effect = "session";
      description = "Sign iCloud in (a code from the owner's devices) and keep the trusted session";
      command = "icloud login";
    };
    inventory = {
      effect = "read";
      description = "What the iCloud account holds, for the migration";
      command = "icloud inventory";
    };
  };

  perSystem =
    { pkgs, config, ... }:
    {
      packages.icloud = pkgs.writeShellApplication {
        name = "icloud";
        runtimeInputs = [
          config.packages.migration-python
          config.packages.pass-cli
          config.packages.secretspec
          config.packages.governance-authorize
          pkgs.coreutils
          pkgs.gnutar
          pkgs.gzip
        ];
        text = builtins.seq top.migration.checked ''
          export PROTON_PASS_KEY_PROVIDER=''${PROTON_PASS_KEY_PROVIDER:-fs}
          usage="usage: icloud login | inventory OUT.json"
          spec=${config.packages.secretspec-toml}
          work=$(mktemp -d)
          chmod 700 "$work"
          trap 'rm -rf "$work"' EXIT
          mkdir "$work/cookies"
          password() {
            pass-cli item view --vault-name ${lib.escapeShellArg vault} \
              --item-title ${lib.escapeShellArg account.login.item} --field password
          }
          restore() {
            # The session expands inside secretspec's environment, not here.
            # shellcheck disable=SC2016
            secretspec run --file "$spec" --profile ${profile} --reason "icloud: restore the session" -- \
              sh -c 'test -n "''${ICLOUD_SESSION:-}" && printf %s "$ICLOUD_SESSION" | base64 -d | tar -xz -C "$1"' _ "$work/cookies" ||
              true
          }
          save() {
            tar -czf - -C "$work/cookies" . | base64 -w0 >"$work/session"
            secretspec set ICLOUD_SESSION --file "$spec" --profile ${profile} \
              --reason "icloud: keep the trusted session" --from-file "$work/session" >/dev/null
            echo "icloud: session kept in Proton Pass" >&2
          }
          case "''${1:-}" in
            login)
              governance-authorize apple:sign-in apple-mirazo
              restore
              fifo=''${ICLOUD_CODE_FIFO:-/tmp/icloud-2fa-code}
              rm -f "$fifo"
              mkfifo -m 600 "$fifo"
              echo "icloud: when Apple's code arrives, it goes into $fifo" >&2
              password | python3 -I ${./_icloud.py} login ${account.login.email} "$work/cookies" "$fifo"
              rm -f "$fifo"
              save
              ;;
            inventory)
              out=''${2:?$usage}
              governance-authorize apple:inventory apple-mirazo
              restore
              password | python3 -I ${./_icloud.py} inventory ${account.login.email} "$work/cookies" "$out"
              save
              ;;
            *) echo "$usage" >&2; exit 2 ;;
          esac
        '';
      };
    };
}
