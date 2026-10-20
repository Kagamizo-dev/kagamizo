# Buying domains, the one Cloudflare step OpenTofu cannot do: the provider's
# cloudflare_registrar_domain only manages a domain you already own.
#
#   registrar check [domain...]            availability and price; defaults to
#                                          every entity's domainCandidates
#   registrar register <domain> <price>    buy it; <price> must equal the
#                                          current registration cost, so
#                                          nothing is charged unconfirmed, and
#                                          this month's spend plus <price> must
#                                          fit cloudflare.monthlyBudgetUsd
#   registrar status <domain>              registration workflow state
#   registrar zone <domain>                the zone ID to declare
#
# Needs CLOUDFLARE_API_TOKEN with Registrar write (secretspec profile
# `registrar`). Registrations are billed to the account's default payment
# method and are non-refundable.
{ config, ... }:
let
  inherit (config.cloudflare.checked) accountId monthlyBudgetUsd;
  inherit (config.identity.checked) entities domains;
in
{
  perSystem =
    { pkgs, lib, ... }:
    let
      candidates = lib.unique (lib.concatMap (e: e.domainCandidates) (lib.attrValues entities));
      # The ledger: every declared Cloudflare registration.
      registrations = lib.filter (r: r != null) (lib.mapAttrsToList (_: d: d.registration) domains);
    in
    {
      packages.registrar = pkgs.writeShellApplication {
        name = "registrar";
        runtimeInputs = [
          pkgs.curl
          pkgs.jq
          pkgs.util-linux # column
        ];
        text = ''
          usage="usage: registrar check [domain...] | register <domain> <price> | status <domain> | zone <domain>"
          : "''${CLOUDFLARE_API_TOKEN:?run it through secretspec: secretspec run --profile registrar -- registrar ...}"
          root="https://api.cloudflare.com/client/v4"
          base="$root/accounts/${accountId}/registrar"
          candidates=${lib.escapeShellArg (builtins.toJSON candidates)}
          registrations=${lib.escapeShellArg (builtins.toJSON registrations)}
          budget=${toString monthlyBudgetUsd}

          api() {
            local method=$1 path=$2 body=''${3:-}
            curl -sS --fail-with-body -X "$method" "$base/$path" \
              -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
              -H "Content-Type: application/json" \
              ''${body:+--data "$body"}
          }

          # Up to 20 names per request; one line per name: name, verdict, price.
          check() {
            jq -cn '$ARGS.positional | _nwise(20)' --args "$@" | while read -r batch; do
              api POST domain-check "$(jq -cn --argjson d "$batch" '{domains: $d}')" |
                jq -r '.result.domains[] |
                  [.name,
                   (if .registrable then "available" else (.reason // "unavailable") end),
                   (.pricing // {} | "\(.registration_cost // "-") \(.currency // "")/yr, renews \(.renewal_cost // "-")")]
                  | @tsv'
            done
          }

          cmd=''${1:?$usage}
          shift
          case "$cmd" in
            check)
              if [ $# -eq 0 ]; then mapfile -t names < <(jq -r '.[]' <<<"$candidates"); set -- "''${names[@]}"; fi
              check "$@" | column -t -s $'\t'
              ;;
            register)
              domain=''${1:?$usage}
              confirm=''${2:?$usage}
              if ! jq -e --arg d "$domain" 'any(. == $d)' <<<"$candidates" >/dev/null; then
                echo "$domain is not a declared candidate; add it to an entity's domainCandidates first." >&2
                exit 1
              fi
              # Check immediately before buying, as the API docs require.
              result=$(api POST domain-check "$(jq -cn --arg d "$domain" '{domains: [$d]}')" | jq -c '.result.domains[0]')
              if [ "$(jq -r .registrable <<<"$result")" != true ]; then
                echo "$domain cannot be registered: $(jq -r '.reason // "unavailable"' <<<"$result")" >&2
                exit 1
              fi
              price=$(jq -r .pricing.registration_cost <<<"$result")
              renewal=$(jq -r .pricing.renewal_cost <<<"$result")
              if [ "$(jq -r .pricing.currency <<<"$result")" != USD ]; then
                echo "$domain is priced in $(jq -r .pricing.currency <<<"$result"); the budget is in USD." >&2
                exit 1
              fi
              if [ "$confirm" != "$price" ]; then
                echo "$domain costs $price USD now; pass exactly that to confirm." >&2
                exit 1
              fi
              # This month's purchases and renewals from the ledger, plus this one.
              month=$(date -u +%Y-%m)
              total=$(jq -n --argjson r "$registrations" --arg m "$month" --argjson p "$price" '
                ([$r[] | select(.month == $m) | .costUsd] | add // 0)
                + ([$r[] | select(.month[5:7] == $m[5:7] and .month < $m) | .renewalUsd] | add // 0)
                + $p')
              if jq -e --argjson t "$total" --argjson b "$budget" -n '$t > $b' >/dev/null; then
                echo "Buying $domain would bring $month to $total USD, over the $budget USD monthly budget." >&2
                exit 1
              fi
              api POST registrations "$(jq -cn --arg d "$domain" '{domain_name: $d, auto_renew: true}')" |
                jq '.result | {domain_name, state, completed}'
              cat <<NIX

          Record it in the ledger, under identity.domains."$domain":
            registrar = "cloudflare";
            registration = { month = "$month"; costUsd = $price; renewalUsd = $renewal; };
          NIX
              ;;
            status)
              domain=''${1:?$usage}
              api GET "registrations/$domain/registration-status" | jq '.result'
              ;;
            zone)
              domain=''${1:?$usage}
              curl -sS --fail-with-body -G "$root/zones" --data-urlencode "name=$domain" \
                -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" | jq -r --arg d "$domain" '.result[0].id // error("no zone named \($d)")'
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
