# Applies ./kagamizo.nix to GitHub. It runs on a GitHub Actions runner
# (.github/workflows/github-bootstrap.yml), because a Claude cloud session
# may only reach its own repository's API. Your part is two approvals the job
# prints: a Proton Pass login link and a GitHub device code.
#
#   1. Proton Pass and gh sign in (both logged out again when it ends)
#   2. gh's token is stored as Kagamizo-LLC/github-token (profile github)
#   3. each verified domain: added to the org; its TXT token is printed for
#      github.verifiedDomains, and once the record resolves it is verified
#   4. each repo: transferred in if declared elsewhere, its visibility,
#      environments (with their branch rules), Actions secrets (piped from
#      the proton-agents profile) and variables. Last, because a session
#      bound to the old location cannot push after the transfer.
#
# Every step is idempotent, so a rerun picks up where the last one stopped.
{
  lib,
  config,
  inputs,
  ...
}:
let
  top = config;
  cfg = config.github;
  cli = import ../_lib/cli.nix {
    inherit lib;
    fx = inputs.nix-effects.lib;
  };
  # A gh api call with a JSON body on stdin.
  api =
    method: endpoint:
    cli.gh "api" {
      endpoint.shell = endpoint;
      inherit method;
      input = "-";
    };
in
{
  perSystem =
    { pkgs, config, ... }:
    {
      packages.gh = pkgs.gh;

      packages.github-bootstrap = pkgs.writeShellApplication {
        name = "github-bootstrap";
        runtimeInputs = [
          config.packages.gh
          config.packages.pass-cli
          config.packages.secretspec
          pkgs.jq
          pkgs.curl
        ];
        # GraphQL and jq variables ($o, $i) live in single-quoted queries.
        excludeShellChecks = [ "SC2016" ];
        # Builds only while the declared plans cover what the repo needs.
        text = builtins.seq top.accounts.checked ''
          export PROTON_PASS_KEY_PROVIDER=fs GH_NO_UPDATE_NOTIFIER=1 GH_PROMPT_DISABLED=1
          unset GH_TOKEN GITHUB_TOKEN
          org=${lib.escapeShellArg cfg.org}
          repos=${lib.escapeShellArg (builtins.toJSON cfg.repos)}
          domains=${lib.escapeShellArg (builtins.toJSON cfg.verifiedDomains)}
          spec=${config.packages.secretspec-toml}
          reason="github-bootstrap: configure $org from parts/github"

          cleanup() {
            ${cli.passCli "logout" { }} >/dev/null 2>&1 || true
            ${cli.gh "auth logout" { hostname = "github.com"; }} >/dev/null 2>&1 || true
          }
          trap cleanup EXIT
          step() { printf '\n==> %s\n' "$*"; }

          step "Proton Pass: approve this link"
          ${cli.passCli "login" { }}

          step "GitHub: approve this code at the URL shown"
          ${
            cli.gh "auth login" {
              hostname = "github.com";
              git-protocol = "https";
              web = true;
              scopes = [
                "admin:org"
                "repo"
                "workflow"
              ];
            }
          } </dev/null

          step "Storing gh's token as Kagamizo-LLC/github-token"
          ${cli.gh "auth token" { }} | secretspec set GITHUB_TOKEN --file "$spec" --profile github \
            --from-file - --reason "$reason" >/dev/null

          # A proton-agents variable into a GitHub secret; never printed.
          secret() { # var gh-args...
            local var=$1 value
            shift
            value=$(secretspec get "$var" --file "$spec" --profile proton-agents --reason "$reason")
            printf %s "$value" | "$@" >/dev/null
            unset value
          }

          graphql() { # query, variables JSON
            jq -n --arg q "$1" --argjson v "$2" '{query: $q, variables: $v}' | ${api "POST" "graphql"}
          }
          for domain in $(jq -r 'keys[]' <<<"$domains"); do
            step "Verifying $domain for $org"
            found=$(graphql 'query($o: String!) { organization(login: $o) { id domains(first: 50) { nodes { id domain isVerified dnsHostName verificationToken } } } }' \
              "$(jq -n --arg o "$org" '{o: $o}')")
            owner=$(jq -r .data.organization.id <<<"$found")
            d=$(jq -c --arg d "$domain" '.data.organization.domains.nodes[] | select(.domain == $d)' <<<"$found")
            if [ -z "$d" ]; then
              d=$(graphql 'mutation($i: ID!, $d: URI!) { addVerifiableDomain(input: {ownerId: $i, domain: $d}) { domain { id domain isVerified dnsHostName verificationToken } } }' \
                "$(jq -n --arg i "$owner" --arg d "$domain" '{i: $i, d: $d}')" | jq -c .data.addVerifiableDomain.domain)
            fi
            if [ "$(jq -r .isVerified <<<"$d")" = true ]; then
              echo "  verified"
              continue
            fi
            host=$(jq -r .dnsHostName <<<"$d")
            token=$(jq -r .verificationToken <<<"$d")
            echo "  declare in parts/github/kagamizo.nix and apply: github.verifiedDomains.\"$domain\" = \"$token\";"
            echo "  waiting for TXT $host"
            for _ in $(seq 80); do
              if curl -fsS -H 'accept: application/dns-json' "https://cloudflare-dns.com/dns-query?name=$host&type=TXT" |
                jq -e --arg t "$token" 'any(.Answer[]?; .data | contains($t))' >/dev/null; then
                graphql 'mutation($i: ID!) { verifyVerifiableDomain(input: {id: $i}) { domain { isVerified } } }' \
                  "$(jq -n --arg i "$(jq -r .id <<<"$d")" '{i: $i}')" | jq -r '"  verified: \(.data.verifyVerifiableDomain.domain.isVerified)"'
                continue 2
              fi
              sleep 30
            done
            echo "  $host did not resolve within 40 minutes; rerun once it does" >&2
            exit 1
          done

          for name in $(jq -r 'keys[]' <<<"$repos"); do
            r=$(jq -c --arg n "$name" '.[$n]' <<<"$repos")
            full="$org/$name"
            from=$(jq -r '.from // empty' <<<"$r")
            if [ -n "$from" ] && ! ${cli.gh "api" { endpoint.shell = "repos/$full"; }} >/dev/null 2>&1; then
              step "Transferring $from/$name to $org"
              jq -n --arg o "$org" '{new_owner: $o}' | ${api "POST" "repos/$from/$name/transfer"} >/dev/null
              for _ in $(seq 60); do
                ${cli.gh "api" { endpoint.shell = "repos/$full"; }} >/dev/null 2>&1 && break
                sleep 5
              done
            fi

            step "$full: visibility, environments, secrets, variables"
            ${cli.gh "repo edit" {
              repository.shell = "$full";
              visibility.shell = "$(jq -r .visibility <<<\"$r\")";
              accept-visibility-change-consequences = true;
            }}
            for env in $(jq -r '.environments | keys[]' <<<"$r"); do
              e=$(jq -c --arg e "$env" '.environments[$e]' <<<"$r")
              jq -n '{deployment_branch_policy: {protected_branches: false, custom_branch_policies: true}}' |
                ${api "PUT" "repos/$full/environments/$env"} >/dev/null
              for branch in $(jq -r '.branches[]' <<<"$e"); do
                # 422 when the rule exists already.
                jq -n --arg b "$branch" '{name: $b, type: "branch"}' |
                  ${api "POST" "repos/$full/environments/$env/deployment-branch-policies"} >/dev/null 2>&1 || true
              done
              for s in $(jq -r '.secrets | keys[]' <<<"$e"); do
                secret "$(jq -r --arg s "$s" '.secrets[$s]' <<<"$e")" ${
                  cli.gh "secret set" {
                    secret-name.shell = "$s";
                    repo.shell = "$full";
                    env.shell = "$env";
                  }
                }
                echo "  secret $s (environment $env)"
              done
            done
            for s in $(jq -r '.secrets | keys[]' <<<"$r"); do
              secret "$(jq -r --arg s "$s" '.secrets[$s]' <<<"$r")" ${
                cli.gh "secret set" {
                  secret-name.shell = "$s";
                  repo.shell = "$full";
                }
              }
              echo "  secret $s"
            done
            for v in $(jq -r '.variables | keys[]' <<<"$r"); do
              ${cli.gh "variable set" {
                variable-name.shell = "$v";
                body.shell = "$(jq -r --arg v \"$v\" '.variables[$v]' <<<\"$r\")";
                repo.shell = "$full";
              }}
              echo "  variable $v"
            done
          done

        '';
      };
    };
}
