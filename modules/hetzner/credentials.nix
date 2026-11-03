# What jingzo-host may hold: every credential it needs, delegated into its
# own vault, typed, scoped and dated. The host's agent token opens only
# that vault (proton.agents.kagamizo-host), never the owner's; each
# delegation names its source, why the host needs it and the day it ends.
#
#   hetzner.host.credentials.<name> = {
#     from = { vault; item; kind; };   # the owner's item: a login or a note
#     to = "host" | "install";         # Kagamizo-Host, or Kagamizo-Install
#                                      # for what is handed over at install
#     item;                            # its title there
#     until;                           # removed on `host-credentials sync`
#     why;                             # after this date
#   }
#
#   nix run .#host-credentials -- sync
#       from the owner's session: copies each live delegation from its
#       source into its vault (pass-cli to pass-cli, never printed; a new
#       copy first, then the old removed), and deletes expired ones.
#
# The host's token itself goes to Kagamizo-Install, from where host-install
# writes it to /var/lib/kagamizo/host-token at install (nixos-anywhere
# --extra-files): the one secret on the host's disk.
{ lib, config, ... }:
let
  inherit (lib) mkOption types;
  cfg = config.hetzner.host.credentials;
  vaults = config.proton.infraVaults;
  allVaults = lib.attrValues vaults ++ config.proton.vaults;
  date = types.strMatching "[0-9]{4}-[0-9]{2}-[0-9]{2}";
in
{
  options.hetzner.host.credentials = mkOption {
    type = types.attrsOf (
      types.submodule (
        { name, ... }:
        {
          options = {
            from = {
              vault = mkOption { type = types.enum allVaults; };
              item = mkOption { type = types.str; };
              kind = mkOption {
                type = types.enum [
                  "login"
                  "note"
                ];
              };
            };
            to = mkOption {
              type = types.enum [
                "host"
                "install"
              ];
              default = "host";
            };
            item = mkOption {
              type = types.strMatching "[a-z][a-z0-9-]*";
              default = name;
            };
            until = mkOption {
              type = date;
              description = "The last day the host holds it; `host-credentials sync` removes it after.";
            };
            why = mkOption { type = types.str; };
          };
        }
      )
    );
    default = { };
    description = "Credentials delegated to jingzo-host, each scoped to its vault and dated.";
  };

  config = {
    hetzner.host.credentials = {
      # The host's own Proton Pass token, handed over at install.
      host-token = {
        from = {
          vault = vaults.root;
          item = "pass-agent-kagamizo-host";
          kind = "note";
        };
        to = "install";
        until = "2027-05-01";
        why = "jingzo-host signs pass-cli in with it at boot (/var/lib/kagamizo/host-token)";
      };
      # The migration off iCloud (../migration): the Apple ID's login and
      # its trusted session, until iCloud is emptied and closed.
      apple-mirazo-login = {
        from = {
          vault = vaults.root;
          item = "Apple";
          kind = "login";
        };
        until = "2026-12-31";
        why = "the iCloud exports sign in as apple-mirazo (pyicloud, icloudpd, rclone)";
      };
      icloud-session = {
        from = {
          vault = config.proton.sessionVaults.mirazo;
          item = "icloud-session";
          kind = "note";
        };
        until = "2026-12-31";
        why = "pyicloud's trusted session, so the host's exports need no new code";
      };
    };

    perSystem =
      { pkgs, config, ... }:
      let
        declared = builtins.toJSON (
          lib.mapAttrs (_: c: {
            inherit (c.from) vault item kind;
            to = vaults.${c.to};
            title = c.item;
            inherit (c) until;
          }) cfg
        );
      in
      {
        packages.host-credentials = pkgs.writeShellApplication {
          name = "host-credentials";
          runtimeInputs = [
            config.packages.pass-cli
            pkgs.jq
            pkgs.coreutils
          ];
          text = ''
            [ "''${1:-}" = sync ] || { echo "usage: host-credentials sync" >&2; exit 2; }
            export PROTON_PASS_KEY_PROVIDER=''${PROTON_PASS_KEY_PROVIDER:-fs}
            today=$(date -u +%F)
            ids() { # vault title -> the ids of items so titled
              pass-cli item list --vault-name "$1" --output json | jq -r --arg t "$2" '.items[] | select(.title == $t) | .id'
            }
            jq -c 'to_entries[]' <<<${lib.escapeShellArg declared} | while read -r e; do
              name=$(jq -r .key <<<"$e"); c=$(jq -c .value <<<"$e")
              from=$(jq -r .vault <<<"$c"); src=$(jq -r .item <<<"$c"); kind=$(jq -r .kind <<<"$c")
              to=$(jq -r .to <<<"$c"); title=$(jq -r .title <<<"$c"); until=$(jq -r .until <<<"$c")
              old=$(ids "$to" "$title")
              if [[ "$today" > "$until" ]]; then
                for id in $old; do
                  share=$(pass-cli item list --vault-name "$to" --output json | jq -r --arg i "$id" '.items[] | select(.id == $i) | .share_id')
                  pass-cli item delete "--share-id=$share" "--item-id=$id" >/dev/null
                done
                echo "  $name: expired ($until), removed from $to"
                continue
              fi
              # The value goes from pass-cli's view straight into pass-cli's
              # create, as JSON on a pipe: never printed, never on disk.
              view=$(pass-cli item view --vault-name "$from" --item-title "$src" --output json 2>/dev/null) ||
                { echo "  $name: no $from/$src yet; skipped" >&2; continue; }
              note="Delegated to jingzo-host from $from/$src until $until (modules/hetzner/credentials.nix: $name). Removed by host-credentials sync after that date."
              case "$kind" in
                note)
                  jq -c --arg t "$title" --arg n "$note" '{title: $t, note: .item.content.note}' <<<"$view" |
                    pass-cli item create note --vault-name "$to" --from-template - >/dev/null ;;
                login)
                  jq -c --arg t "$title" --arg n "$note" '.item.content.content.Login as $l |
                    {title: $t, username: $l.username, email: $l.email, password: $l.password, totp_uri: null, urls: ($l.urls // [])}' <<<"$view" |
                    pass-cli item create login --vault-name "$to" --from-template - >/dev/null ;;
              esac
              unset view
              # The new copy exists; only now does the old one go.
              for id in $old; do
                share=$(pass-cli item list --vault-name "$to" --output json | jq -r --arg i "$id" '.items[] | select(.id == $i) | .share_id')
                pass-cli item delete "--share-id=$share" "--item-id=$id" >/dev/null
              done
              echo "  $name: $from/$src -> $to/$title (until $until)"
            done
          '';
        };
      };
  };
}
