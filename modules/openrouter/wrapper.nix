# `nix run .#openrouter -- <plan|apply|models|credits>`: see ./openrouter.nix.
# OpenRouter has no CLI of its own, so this speaks its management API
# (https://openrouter.ai/docs/api/api-reference/api-keys/create-keys) with
# curl, under the secretspec profile `openrouter`.
{
  lib,
  config,
  ...
}:
let
  top = config;
  cfg = config.openrouter;
  # Keys are named after their declaration, so ours are told apart from any
  # made by hand.
  keys = lib.mapAttrs (name: k: k // { label = "kagamizo/${name}"; }) cfg.keys;
in
{
  perSystem =
    { pkgs, config, ... }:
    let
      spec = config.packages.secretspec-toml;

      run = pkgs.writeShellApplication {
        name = "openrouter-run";
        runtimeInputs = [
          pkgs.curl
          pkgs.jq
          config.packages.secretspec
          config.packages.pass-cli
        ];
        text = ''
          : "''${OPENROUTER_MANAGEMENT_KEY:?}"
          keys=${lib.escapeShellArg (builtins.toJSON keys)}
          models=${lib.escapeShellArg (builtins.toJSON cfg.models)}
          spec=${spec}
          reason="openrouter: keys from modules/openrouter"

          api() { # method path [json body]
            curl -fsS -X "$1" -H "Authorization: Bearer $OPENROUTER_MANAGEMENT_KEY" \
              -H 'Content-Type: application/json' "https://openrouter.ai/api/v1$2" ''${3:+-d "$3"}
          }
          live() { api GET /keys | jq -c '[.data[] | select(.name | startswith("kagamizo/"))]'; }
          stored() { # name -> whether its secret is in Proton Pass (never printed)
            secretspec get "$(jq -r --arg n "$1" '.[$n].variable' <<<"$keys")" --file "$spec" \
              --profile "$(jq -r --arg n "$1" '.[$n].profile' <<<"$keys")" --reason "$reason" >/dev/null 2>&1
          }
          # Creates a key and pipes its value, shown only once, into its profile.
          mint() { # name
            local k body
            k=$(jq -c --arg n "$1" '.[$n]' <<<"$keys")
            body=$(jq -c '{name: .label, limit: .limitUsd, limit_reset: .reset}' <<<"$k")
            api POST /keys "$body" | jq -j .key |
              secretspec set "$(jq -r .variable <<<"$k")" --file "$spec" --profile "$(jq -r .profile <<<"$k")" \
                --from-file - --reason "$reason: mint $1" >/dev/null
          }

          case "''${1:-}" in
            plan)
              l=$(live)
              for name in $(jq -r 'keys[]' <<<"$keys"); do
                k=$(jq -c --arg n "$name" '.[$n]' <<<"$keys")
                have=$(jq -c --arg l "$(jq -r .label <<<"$k")" 'map(select(.name == $l))[0] // empty' <<<"$l")
                if stored "$name"; then s="stored"; else s="not stored"; fi
                if [ -z "$have" ]; then
                  echo "+ create  $name: \$$(jq -r .limitUsd <<<"$k")/$(jq -r .reset <<<"$k") -> $(jq -r '"\(.profile)/\(.variable)"' <<<"$k")"
                elif [ "$s" = "not stored" ]; then
                  echo "~ re-mint $name: its secret is not stored"
                elif ! jq -e --argjson k "$k" '.limit == $k.limitUsd and .limit_reset == $k.reset' <<<"$have" >/dev/null; then
                  echo "~ update  $name: cap \$$(jq -r .limit <<<"$have")/$(jq -r .limit_reset <<<"$have") -> \$$(jq -r .limitUsd <<<"$k")/$(jq -r .reset <<<"$k")"
                else
                  echo "  ok      $name: used \$$(jq -r '.usage // 0' <<<"$have") of \$$(jq -r .limit <<<"$have")/$(jq -r .limit_reset <<<"$have"), $s"
                fi
              done
              jq -r --argjson k "$keys" '.[] | select(.name as $n | [$k[].label] | index($n) | not) | "- delete  \(.name) (no longer declared)"' <<<"$l"
              ;;
            apply)
              l=$(live)
              for name in $(jq -r 'keys[]' <<<"$keys"); do
                k=$(jq -c --arg n "$name" '.[$n]' <<<"$keys")
                hash=$(jq -r --arg l "$(jq -r .label <<<"$k")" 'map(select(.name == $l))[0].hash // empty' <<<"$l")
                if [ -n "$hash" ] && ! stored "$name"; then
                  api DELETE "/keys/$hash" >/dev/null
                  hash=""
                fi
                if [ -z "$hash" ]; then
                  mint "$name"
                  echo "minted $name -> $(jq -r '"\(.profile)/\(.variable)"' <<<"$k")"
                else
                  api PATCH "/keys/$hash" "$(jq -c '{limit: .limitUsd, limit_reset: .reset}' <<<"$k")" >/dev/null
                  echo "ok $name"
                fi
              done
              jq -r --argjson k "$keys" '.[] | select(.name as $n | [$k[].label] | index($n) | not) | .hash' <<<"$l" |
                while read -r hash; do
                  api DELETE "/keys/$hash" >/dev/null
                  echo "deleted undeclared key $hash"
                done
              ;;
            models)
              offered=$(curl -fsS https://openrouter.ai/api/v1/models | jq -c '[.data[].id]')
              missing=$(jq -c --argjson o "$offered" 'map(select(. as $m | $o | index($m) | not))' <<<"$models")
              if [ "$missing" != "[]" ]; then
                echo "no longer offered: $missing" >&2
                exit 1
              fi
              echo "all $(jq length <<<"$models") models offered"
              ;;
            credits)
              api GET /credits | jq -r '.data | "credits \(.total_credits), used \(.total_usage), left \(.total_credits - .total_usage)"'
              ;;
            *)
              echo "usage: openrouter <plan|apply|models|credits>" >&2
              exit 2
              ;;
          esac
        '';
      };
    in
    {
      packages.openrouter = pkgs.writeShellApplication {
        name = "openrouter";
        runtimeInputs = [
          config.packages.secretspec
          config.packages.pass-cli
        ];
        # Builds only while the declared plans cover what the repo needs.
        text = builtins.seq top.accounts.checked ''
          export PROTON_PASS_KEY_PROVIDER=''${PROTON_PASS_KEY_PROVIDER:-fs}
          exec secretspec run --file ${spec} --profile openrouter \
            --reason "openrouter $*" -- ${run}/bin/openrouter-run "$@"
        '';
      };
    };
}
