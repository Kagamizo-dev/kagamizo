# `northwest`: the Northwest account through its MCP server (./_client.py),
# one OAuth session per account, kept in its entity's sessions vault as
# NORTHWEST_SESSION and rewritten whenever the client refreshes it.
#
#   northwest [--account A] login            approval link, then wait (10 min)
#   northwest callback <address>             hand a phone's failed 127.0.0.1
#                                            page to the waiting login
#   northwest [--account A] status           whether the session works
#   northwest [--account A] tools            the server's tools/list
#   northwest [--account A] catalog          tools/list as _json/tools.json
#   northwest [--account A] call TOOL [JSON] call one tool
#
# Every command but callback asks governance-authorize first, as whoever
# KAGAMIZO_PRINCIPAL names: an Orca agent may call only the tools its grants
# cover (modules/governance), and only for the entity it serves.
{ lib, config, ... }:
let
  top = config;
  secret = import ../_lib/secret.nix;
  accounts = lib.filterAttrs (_: a: a.provider == "northwest") config.accounts.held;
  profile = name: "northwest-${lib.removePrefix "northwest-" name}";
in
{
  secrets.profiles = lib.mapAttrs' (
    name: a:
    lib.nameValuePair (profile name) {
      defaults.providers = [ "${a.owner}-sessions" ];
      NORTHWEST_SESSION =
        secret "Northwest OAuth session for ${name}, rewritten on every use" "northwest-session"
        // {
          required = false;
        };
    }
  ) accounts;

  accounts.demands = lib.mapAttrsToList (name: _: {
    account = name;
    capability = "mcpServer";
    need = true;
    why = "northwest (${name}) runs on Northwest's MCP server";
  }) accounts;

  perSystem =
    { pkgs, config, ... }:
    let
      spec = config.packages.secretspec-toml;
      run = pkgs.writeShellApplication {
        name = "northwest-run";
        runtimeInputs = [
          config.packages.secretspec
          pkgs.coreutils
          pkgs.jq
        ];
        text = ''
          profile=$1
          shift
          dir=$(mktemp -d)
          chmod 700 "$dir"
          export NORTHWEST_SESSION_FILE=$dir/session.json
          if [ -n "''${NORTHWEST_SESSION:-}" ]; then
            printf %s "$NORTHWEST_SESSION" >"$NORTHWEST_SESSION_FILE"
            chmod 600 "$NORTHWEST_SESSION_FILE"
          fi
          before=$(sha256sum "$NORTHWEST_SESSION_FILE" 2>/dev/null || true)
          unset NORTHWEST_SESSION
          save() {
            if [ -s "$NORTHWEST_SESSION_FILE" ] && [ "$(sha256sum "$NORTHWEST_SESSION_FILE")" != "$before" ]; then
              secretspec set NORTHWEST_SESSION --file ${spec} --profile "$profile" \
                --from-file "$NORTHWEST_SESSION_FILE" --reason "northwest: save the refreshed session" >/dev/null
            fi
            rm -rf "$dir"
          }
          trap save EXIT
          client() { ${pkgs.python3}/bin/python3 -I ${./_client.py} "$@"; }
          if [ "$1" = catalog ]; then
            client tools | jq --arg s "tools/list of ${"$"}{NORTHWEST_MCP_URL:-https://mcp.northwestregisteredagent.com}, $(date -u +%F)" \
              '{_source: $s, tools: [.[] | {name, description: ((.description // "") | split("\n")[0])}] | sort_by(.name)}'
          else
            client "$@"
          fi
        '';
      };
    in
    {
      packages.northwest = pkgs.writeShellApplication {
        name = "northwest";
        runtimeInputs = [
          config.packages.secretspec
          config.packages.pass-cli
          config.packages.governance-authorize
          pkgs.curl
        ];
        text = builtins.seq top.accounts.checked ''
          export PROTON_PASS_KEY_PROVIDER=''${PROTON_PASS_KEY_PROVIDER:-fs}
          accounts=(${lib.concatStringsSep " " (lib.attrNames accounts)})
          usage="usage: northwest [--account ''${accounts[*]}] <login|status|tools|catalog|call TOOL [JSON]> | callback <address>"
          account=
          if [ "''${1:-}" = --account ]; then
            account=''${2:?$usage}
            shift 2
          fi
          cmd=''${1:?$usage}

          if [ "$cmd" = callback ]; then
            address=''${2:?$usage}
            case "$address" in
              http://127.0.0.1:*/callback\?*) ;;
              *) echo "northwest: not a 127.0.0.1 callback address" >&2; exit 2 ;;
            esac
            curl -fsS -o /dev/null "$address" && echo "northwest: delivered" >&2
            exit
          fi

          if [ -z "$account" ]; then
            [ ''${#accounts[@]} -eq 1 ] || { echo "northwest: name the account: ''${accounts[*]}" >&2; exit 2; }
            account=''${accounts[0]}
          fi
          case " ''${accounts[*]} " in
            *" $account "*) ;;
            *) echo "northwest: no account $account; declared: ''${accounts[*]}" >&2; exit 2 ;;
          esac

          case "$cmd" in
            login) action=login ;;
            status | tools | catalog) action=tools ;;
            call) action=''${2:?$usage} ;;
            *) echo "$usage" >&2; exit 2 ;;
          esac
          governance-authorize "northwest:$action" "$account"

          profile=northwest-''${account#northwest-}
          exec secretspec run --file ${config.packages.secretspec-toml} --profile "$profile" \
            --reason "northwest $cmd ($account)" -- ${run}/bin/northwest-run "$profile" "$@"
        '';
      };
    };
}
