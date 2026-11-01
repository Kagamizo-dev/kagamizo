# Proton Pass is the authority on who signs in where. `identity-audit` reads
# every held account's login item from its owner's vault, addresses only
# (username, when it is one, and email; never a password, a code or a note),
# and holds it against the declaration: the address the account signs in
# with (accounts.held.<a>.login), on its owner's domain.
#
#   nix run .#identity-audit   one line per account, then every login in a
#                              company's vault that no account declares;
#                              exits 1 on any mismatch
#
# governance-authorize makes the same reading before every action, so an
# account this lists as wrong cannot be acted on until it is right.
{ lib, config, ... }:
let
  inherit (config.identity.checked) entities;
  accounts = lib.mapAttrs (_: a: {
    inherit (a) owner status;
    inherit (entities.${a.owner}) vault;
    inherit (a.login) item email;
    inherit (a) credential;
  }) config.accounts.held;
  # The fields each Proton Pass app template has, as [name, kind] pairs.
  templateFields = lib.mapAttrs (
    _: t:
    lib.sort (a: b: lib.head a < lib.head b) (
      lib.mapAttrsToList (n: k: [
        n
        k
      ]) t.fields
    )
  ) (lib.importJSON ../catalog/_json/pass-items.json).appTemplates;
  # A company's vault holds only its accounts' logins; a person's holds
  # their whole life, so only declared items are read there.
  companyVaults = lib.mapAttrsToList (_: e: e.vault) (
    lib.filterAttrs (_: e: e.kind != "person") entities
  );
in
{
  perSystem =
    { pkgs, config, ... }:
    {
      # `pass-login VAULT ITEM`: the addresses on a login item (its username,
      # when it is one, and its email), lowercased, one per line; nothing if
      # the vault has no single login item of that title. Login items only,
      # so an alias of the same name is never read.
      packages = {
        pass-login = pkgs.writeShellApplication {
          name = "pass-login";
          runtimeInputs = [
            config.packages.pass-cli
            pkgs.jq
            pkgs.coreutils
            pkgs.gnugrep
          ];
          text = ''
            export PROTON_PASS_KEY_PROVIDER=''${PROTON_PASS_KEY_PROVIDER:-fs}
            vault=''${1:?usage: pass-login VAULT ITEM} item=''${2:?usage: pass-login VAULT ITEM}
            ids=$(pass-cli item list "$vault" --filter-type login --output json 2>/dev/null |
              jq -r --arg t "$item" '(.items // .)[] | select(.title == $t) | .id' || true)
            [ -n "$ids" ] && [ "$(wc -l <<<"$ids")" = 1 ] || exit 0
            for f in username email; do
              pass-cli item view --vault-name "$vault" --item-id "$ids" --field "$f" 2>/dev/null || true
              echo
            done | tr '[:upper:]' '[:lower:]' | grep @ | sort -u || true
          '';
        };

        # `pass-credential VAULT ITEM TEMPLATE`: `ok` when the vault has exactly
        # one custom item of that title and its fields are the template's, by
        # name and kind; nothing otherwise. Reads names and kinds only, never
        # a value.
        pass-credential = pkgs.writeShellApplication {
          name = "pass-credential";
          runtimeInputs = [
            config.packages.pass-cli
            pkgs.jq
            pkgs.coreutils
          ];
          text = ''
            export PROTON_PASS_KEY_PROVIDER=''${PROTON_PASS_KEY_PROVIDER:-fs}
            vault=''${1:?usage: pass-credential VAULT ITEM TEMPLATE}
            item=''${2:?usage: pass-credential VAULT ITEM TEMPLATE}
            template=''${3:?usage: pass-credential VAULT ITEM TEMPLATE}
            want=$(jq -c --arg t "$template" '.[$t] // empty' ${pkgs.writeText "templates.json" (builtins.toJSON templateFields)})
            [ -n "$want" ] || exit 0
            ids=$(pass-cli item list "$vault" --filter-type custom --output json 2>/dev/null |
              jq -r --arg t "$item" '(.items // .)[] | select(.title == $t) | .id' || true)
            [ -n "$ids" ] && [ "$(wc -l <<<"$ids")" = 1 ] || exit 0
            seen=$(pass-cli item view --vault-name "$vault" --item-id "$ids" --output json 2>/dev/null |
              jq -c '[.. | objects | select(has("name") and has("content") and (.content | type) == "object")
                      | [.name, (.content | keys[0] | ascii_downcase)]] | sort' || true)
            [ "$seen" = "$want" ] && echo ok
            true
          '';
        };

        identity-audit = pkgs.writeShellApplication {
          name = "identity-audit";
          runtimeInputs = [
            config.packages.pass-cli
            config.packages.pass-login
            config.packages.pass-credential
            pkgs.jq
          ];
          text = ''
            export PROTON_PASS_KEY_PROVIDER=''${PROTON_PASS_KEY_PROVIDER:-fs}
            accounts=${lib.escapeShellArg (builtins.toJSON accounts)}
            bad=0
            printf '%-20s %-9s %-30s %s\n' ACCOUNT STATUS DECLARED "PROTON PASS (vault / item)"
            while IFS=$'\t' read -r name status vault item email; do
              seen=$(pass-login "$vault" "$item" | paste -sd, -)
              if [ "$seen" = "$email" ]; then
                verdict=ok
              else
                verdict="''${seen:-no login item}"
                bad=1
              fi
              printf '%-20s %-9s %-30s %s  (%s / %s)\n' "$name" "$status" "$email" "$verdict" "$vault" "$item"
            done < <(jq -r 'to_entries[] | [.key, .value.status, .value.vault, .value.item, .value.email] | @tsv' <<<"$accounts")

            echo
            echo "API credentials (custom items, by field names and kinds):"
            while IFS=$'\t' read -r name vault item template; do
              if [ "$(pass-credential "$vault" "$item" "$template")" = ok ]; then
                verdict=ok
              else
                verdict="missing, or not a $template"
                bad=1
              fi
              printf '%-20s %-20s %s  (%s / %s)\n' "$name" "$template" "$verdict" "$vault" "$item"
            done < <(jq -r 'to_entries[] | select(.value.credential != null)
              | [.key, .value.vault, .value.credential.item, .value.credential.template] | @tsv' <<<"$accounts")

            echo
            echo "Logins in a company's vault that no account declares:"
            for vault in ${lib.escapeShellArgs companyVaults}; do
              pass-cli item list "$vault" --filter-type login --output json 2>/dev/null |
                jq -r --arg v "$vault" --argjson a "$accounts" \
                  '[$a[] | select(.vault == $v) | .item] as $known
                   | (.items // .)[] | select(.title as $t | $known | index($t) | not) | "  \($v) / \(.title)"'
            done
            exit "$bad"
          '';
        };
      };
    };
}
