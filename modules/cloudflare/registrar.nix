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
#   registrar ledger                       live registrations missing from the
#                                          declared ledger (the budget counts
#                                          only declared ones)
#
# Every call is a typed `cf` command (../_lib/cli.nix, catalog/cf.json),
# authenticated by your `cloudflare-login` session: account tokens cannot hold
# Registrar, so no stored token can buy a domain.
# Registrations are billed to the account's default payment method and are
# non-refundable.
{
  config,
  lib,
  inputs,
  ...
}:
let
  top = config;
  inherit (config.cloudflare.checked) accountId monthlyBudgetUsd;
  inherit (config.identity.checked) entities domains;
  cli = import ../_lib/cli.nix {
    inherit lib;
    fx = inputs.nix-effects.lib;
  };
  candidates = lib.unique (lib.concatMap (e: e.domainCandidates) (lib.attrValues entities));
  # The ledger: every declared Cloudflare registration, by domain.
  registrations = lib.filterAttrs (_: r: r != null) (lib.mapAttrs (_: d: d.registration) domains);
in
{
  accounts.demands = [
    {
      account = "cloudflare";
      capability = "registrarAtCost";
      need = true;
      why = "registrar register, budgeted at Cloudflare's registration price";
    }
  ];

  perSystem =
    { pkgs, config, ... }:
    {
      packages.registrar = pkgs.writeShellApplication {
        name = "registrar";
        runtimeInputs = [
          config.packages.cf
          pkgs.jq
          pkgs.util-linux # column
        ];
        # Builds only while the declared plans cover what the repo needs.
        text = builtins.seq top.accounts.checked ''
          usage="usage: registrar check [domain...] | register <domain> <price> | status <domain> | zone <domain> | ledger"
          export CLOUDFLARE_ACCOUNT_ID=${accountId}
          candidates=${lib.escapeShellArg (builtins.toJSON candidates)}
          registrations=${lib.escapeShellArg (builtins.toJSON registrations)}
          budget=${toString monthlyBudgetUsd}

          # cf prints the API result; accept it with or without the envelope.
          result() { jq -c '.result // .'; }
          # List commands print a bare array.
          items() { jq -c 'if type == "array" then . else .result end'; }

          # One line per name: name, verdict, price. At most 20 names per call.
          check() {
            ${cli.cf "registrar registrations check" { domains.shell = "$@"; }} | result |
              jq -r '.domains[] |
                [.name,
                 (if .registrable then "available" else (.reason // "unavailable") end),
                 (.pricing // {} | "\(.registration_cost // "-") \(.currency // "")/yr, renews \(.renewal_cost // "-")")]
                | @tsv'
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
              if ! jq -e --arg d "$domain" 'any(.[]; . == $d)' <<<"$candidates" >/dev/null; then
                echo "$domain is not a declared candidate; add it to an entity's domainCandidates first." >&2
                exit 1
              fi
              # Check immediately before buying, as the API docs require.
              result=$(${
                cli.cf "registrar registrations check" { domains.shell = "$domain"; }
              } | result | jq -c '.domains[0]')
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
              # --force skips cf's own prompt: the price and budget checks above
              # are the confirmation.
              ${
                cli.cf "registrar registrations create" {
                  domain-name.shell = "$domain";
                  auto-renew = true;
                  force = true;
                }
              } | result | jq '{domain_name, state, completed}'
              cat <<NIX

          Record it in the ledger, under identity.domains."$domain":
            registrar = "cloudflare";
            registration = { month = "$month"; costUsd = $price; renewalUsd = $renewal; };
          NIX
              ;;
            status)
              domain=''${1:?$usage}
              ${
                cli.cf "registrar registrations get-registration-status" { domain-name.shell = "$domain"; }
              } | result
              ;;
            zone)
              domain=''${1:?$usage}
              ${cli.cf "zones list" { name.shell = "$domain"; }} | items |
                jq -r '.[0].id // error("no such zone")'
              ;;
            ledger)
              ${cli.cf "registrar registrations list" { }} | items |
                jq -r --argjson r "$registrations" '.[] | .domain_name
                  | select(. as $d | $r | has($d) | not) | "undeclared: \(.)"'
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
