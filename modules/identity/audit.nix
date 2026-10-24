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
  }) config.accounts.held;
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
      packages.pass-login = pkgs.writeShellApplication {
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

      packages.identity-audit = pkgs.writeShellApplication {
        name = "identity-audit";
        runtimeInputs = [
          config.packages.pass-cli
          config.packages.pass-login
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
}
