# Mints the token profiles in ./tokens.nix, with your `cloudflare-login`
# session as the only root credential:
#
#   bootstrap plan            declared against live: permission groups, tokens
#                             (Cloudflare only; `proton plan` diffs items)
#   bootstrap apply           mint missing tokens, re-sync the permissions of
#                             existing ones, and write every new value straight
#                             into its vault (needs pass-cli signed in);
#                             generates the state passphrase once
#   bootstrap rotate <name>   new value for one token, stored the same way
#
# Values never reach the terminal: each goes from cf's output into secretspec.
# A token whose value could not be stored is deleted again. Tokens are account
# owned and named nix-images-<profile>; every call is a typed `cf` command.
{
  config,
  lib,
  inputs,
  ...
}:
let
  top = config;
  cloudflare = config.cloudflare.checked;
  inherit (cloudflare) accountId tokens;
  inherit (config.proton.secretspec) providers profiles;
  cli = import ../_lib/cli.nix {
    inherit lib;
    fx = inputs.nix-effects.lib;
  };

  zoneIds = lib.filter (id: id != null) (
    lib.mapAttrsToList (_: d: d.zoneId) config.identity.checked.domains
  );
  account = "com.cloudflare.api.account.${accountId}";
  zoneScope = "com.cloudflare.api.account.zone";
  # What each kind of grant covers, and the permission group scope it needs.
  grants = {
    zone = {
      scope = zoneScope;
      resources.${account} = lib.genAttrs (map (id: "${zoneScope}.${id}") zoneIds) (_: "*");
    };
    allZones = {
      scope = zoneScope;
      resources.${account}."${zoneScope}.*" = "*";
    };
    account = {
      scope = "com.cloudflare.api.account";
      resources.${account} = "*";
    };
  };

  # Policies with permission groups still named; the script swaps in IDs.
  policies =
    profile:
    lib.concatLists (
      lib.mapAttrsToList (
        kind: g:
        lib.optional (profile.${kind} != [ ] && g.resources != { ${account} = { }; }) {
          effect = "allow";
          permission_groups = map (name: {
            inherit name;
            inherit (g) scope;
          }) profile.${kind};
          inherit (g) resources;
        }
      ) grants
    );

  # Where a profile's value goes, checked against secretspec.
  stored =
    name: profile:
    let
      problems = lib.concatMap (
        p:
        if !(profiles ? ${p}) then
          [ "storeIn: no secretspec profile `${p}`" ]
        else
          lib.optional (
            !(profiles.${p} ? CLOUDFLARE_API_TOKEN)
          ) "storeIn: profile `${p}` declares no CLOUDFLARE_API_TOKEN"
      ) profile.storeIn;
    in
    if problems == [ ] then
      {
        policies = policies profile;
        targets = map (p: {
          profile = p;
          vault = lib.removePrefix "protonpass://" providers.${lib.head profiles.${p}.defaults.providers};
        }) profile.storeIn;
      }
    else
      throw "cloudflare.tokens.${name}:\n${lib.concatMapStrings (p: "  - ${p}\n") problems}";

  declared = lib.mapAttrs stored tokens;

  stateVault = config.proton.infraVaults.state;
in
{
  perSystem =
    { pkgs, config, ... }:
    {
      packages.bootstrap = pkgs.writeShellApplication {
        name = "bootstrap";
        runtimeInputs = [
          config.packages.cf
          config.packages.pass-cli
          config.packages.secretspec
          pkgs.jq
          pkgs.openssl
          pkgs.coreutils
        ];
        # Builds only while the declared plans cover what the repo needs.
        text = builtins.seq top.accounts.checked ''
          usage="usage: bootstrap plan | apply | rotate <name>"
          export CLOUDFLARE_ACCOUNT_ID=${accountId}
          # Containers have no keyring; without this pass-cli logs itself out.
          export PROTON_PASS_KEY_PROVIDER=''${PROTON_PASS_KEY_PROVIDER:-fs}
          declared=${lib.escapeShellArg (builtins.toJSON declared)}
          spec=${config.packages.secretspec-toml}
          expiry=${lib.escapeShellArg cloudflare.tokenExpiry}

          result() { jq -c '.result // .'; }
          items() { jq -c 'if type == "array" then . else .result end'; }

          # Every declared permission group, resolved by name and scope. Fails
          # naming any Cloudflare does not offer account tokens.
          groups=$(${cli.cf "accounts tokens permission-groups list" { }} | items)
          unknown=$(jq -r --argjson g "$groups" '
            [.[].policies[].permission_groups[]] | unique[]
            | select(. as $w | $g | any(.name == $w.name and (.scopes | any(. == $w.scope))) | not)
            | "  \(.name) (\(.scope))"' <<<"$declared")
          if [ -n "$unknown" ]; then
            printf 'Cloudflare offers account tokens no such permission group:\n%s\nFix the name in parts/cloudflare/tokens.nix.\n' "$unknown" >&2
            exit 1
          fi
          # A profile's policies with group IDs in place of names.
          resolved() {
            jq -c --arg n "$1" --argjson g "$groups" '.[$n].policies | map(
              .permission_groups |= map(. as $w | {id: first($g[] | select(.name == $w.name and (.scopes | any(. == $w.scope))) | .id)}))' \
              <<<"$declared"
          }

          live=$(${cli.cf "accounts tokens list" { per-page = 50; }} | items)
          idOf() { jq -r --arg n "nix-images-$1" '[.[] | select(.name == $n)][0].id // empty' <<<"$live"; }

          signedIn() {
            if ! ${cli.passCli "info" { }} >/dev/null 2>&1; then
              echo "pass-cli is not signed in; run pass-cli login first." >&2
              exit 1
            fi
          }
          titles() {
            ${
              cli.passCli "item list" {
                vault-name.shell = "$1";
                output = "json";
              }
            } | jq -c '[.items[].title]'
          }
          put() { # profile var: value on stdin
            secretspec set "$2" --file "$spec" --profile "$1" --from-file - \
              --reason "bootstrap: store $2 for profile $1" >/dev/null
          }

          # Store a new token value (JSON with id and value on stdin) in every
          # vault the profile names.
          store() {
            local name=$1 value
            value=$(jq -r .value)
            for p in $(jq -r --arg n "$name" '.[$n].targets[].profile' <<<"$declared"); do
              printf %s "$value" | put "$p" CLOUDFLARE_API_TOKEN
              echo "  stored $name in profile $p"
            done
          }

          cmd=''${1:?$usage}
          shift
          case "$cmd" in
            plan)
              echo "  ok        permission groups (all resolve)"
              for name in $(jq -r 'keys[]' <<<"$declared"); do
                vaults=$(jq -r --arg n "$name" '[.[$n].targets[].vault] | join(", ")' <<<"$declared")
                if [ -n "$(idOf "$name")" ]; then
                  echo "~ sync      nix-images-$name (permissions only)"
                else
                  echo "+ mint      nix-images-$name -> $vaults"
                fi
              done
              ;;
            apply)
              signedIn

              # The state passphrase, once, in the state vault every state
              # reader shares.
              if ! titles ${stateVault} | jq -e 'index("tofu-state-passphrase")' >/dev/null; then
                openssl rand -base64 32 | tr -d '\n' | put ci TOFU_STATE_PASSPHRASE
                echo "generated tofu-state-passphrase in ${stateVault}"
              fi

              for name in $(jq -r 'keys[]' <<<"$declared"); do
                id=$(idOf "$name")
                if [ -n "$id" ]; then
                  ${
                    cli.cf "accounts tokens update" {
                      token-id.shell = "$id";
                      name.shell = "nix-images-$name";
                      policies.shell = ''$(resolved "$name")'';
                      expires-on.shell = "$expiry";
                    }
                  } >/dev/null
                  echo "synced nix-images-$name"
                else
                  token=$(${
                    cli.cf "accounts tokens create" {
                      name.shell = "nix-images-$name";
                      policies.shell = ''$(resolved "$name")'';
                      expires-on.shell = "$expiry";
                    }
                  } | result)
                  echo "minted nix-images-$name"
                  if ! store "$name" <<<"$token"; then
                    ${
                      cli.cf "accounts tokens delete" { token-id.shell = ''$(jq -r .id <<<"$token")''; }
                    } >/dev/null
                    echo "could not store nix-images-$name; deleted it again" >&2
                    exit 1
                  fi
                  unset token
                fi
              done
              ;;
            rotate)
              name=''${1:?$usage}
              signedIn
              id=$(idOf "$name")
              [ -n "$id" ] || { echo "nix-images-$name does not exist; run apply" >&2; exit 1; }
              value=$(${
                cli.cf "accounts tokens roll" { token-id.shell = "$id"; }
              } | result | jq -r 'if type == "string" then . else .value end')
              jq -n --arg id "$id" --arg v "$value" '{id: $id, value: $v}' | store "$name"
              unset value
              echo "rotated nix-images-$name"
              ;;
            *)
              echo "$usage" >&2
              exit 2
              ;;
          esac
        '';
      };
    };
}
