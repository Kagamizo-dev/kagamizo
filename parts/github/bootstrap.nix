# Applies ./kagamizo.nix to GitHub. It runs on a GitHub Actions runner
# (.github/workflows/github-bootstrap.yml), because a Claude cloud session
# may only reach its own repository's API. Your part is the approvals the job
# posts: a Proton Pass login link, and a GitHub device code when the stored
# token no longer works.
#
#   1. Proton Pass and gh sign in (both logged out again when it ends)
#   2. gh's token is stored as Kagamizo-LLC/github-token (profile github);
#      later runs sign in with it, and need a device code only once it fails
#   3. each verified domain: added to the org; its TXT token is printed for
#      github.verifiedDomains, and once the record resolves it is verified
#   4. each repo: transferred in if declared elsewhere, or created and
#      seeded with the commit this job runs from as `main`; then its
#      visibility, environments (with their branch rules), Actions secrets
#      (piped from the proton-agents profile) and variables. Last, because a
#      session bound to the old location cannot push after the transfer.
#   5. repos declared archived: archived, after everything else.
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
          pkgs.git
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

          # Job logs are only readable once a job ends, so each approval is
          # also posted on the approvals issue of the repo this job runs in
          # (found by its title, opened if missing), where a session can relay
          # it, and deleted once it is approved or has expired.
          issues="https://api.github.com/repos/$GITHUB_REPOSITORY/issues"
          relayApi() { # curl args...
            curl -fsS -H "Authorization: Bearer $RELAY_TOKEN" -H 'Accept: application/vnd.github+json' "$@"
          }
          title="github-bootstrap approvals"
          issue=$(relayApi "$issues?state=open&per_page=100" | jq -r --arg t "$title" 'map(select(.title == $t and (has("pull_request") | not)))[0].number // empty')
          if [ -z "$issue" ]; then
            issue=$(relayApi -X POST "$issues" -d "$(jq -n --arg t "$title" \
              '{title: $t, body: "`github-bootstrap` posts each approval it waits for here, and deletes it once approved or expired. See `parts/github/bootstrap.nix`."}')" | jq -r .number)
          fi
          relay() { # message -> comment id
            relayApi -X POST "$issues/$issue/comments" -d "$(jq -n --arg b "$1" '{body: $b}')" | jq -r .id
          }
          unrelay() {
            relayApi -X DELETE "$issues/comments/$1" >/dev/null || true
          }
          # Runs a login in the background, relays the first match of a
          # pattern in its output, and waits for it to finish.
          approve() { # label pattern command...
            local label=$1 pattern=$2 out pid found="" id="" status=0
            shift 2
            out=$(mktemp)
            "$@" </dev/null >"$out" 2>&1 &
            pid=$!
            while kill -0 "$pid" 2>/dev/null && [ -z "$found" ]; do
              found=$(grep -oE "$pattern" "$out" | head -1 || true)
              sleep 1
            done
            [ -n "$found" ] || found=$(grep -oE "$pattern" "$out" | head -1 || true)
            if [ -n "$found" ]; then id=$(relay "$label: $found"); fi
            wait "$pid" || status=$?
            [ -z "$id" ] || unrelay "$id"
            cat "$out"
            rm -f "$out"
            return "$status"
          }

          # Each login gives up after 10 minutes; offer a fresh one, three times.
          retry() { local n; for n in 1 2 3; do "$@" && return 0; echo "attempt $n expired" >&2; done; return 1; }

          step "Proton Pass: approve the link"
          retry approve "Proton Pass login, approve" 'https://account\.proton\.me/[^[:space:]]+' ${cli.passCli "login" { }}

          # The token a previous run stored, if GitHub still accepts it; a
          # device code only when it is missing, expired or revoked.
          step "GitHub: the stored token"
          if secretspec get GITHUB_TOKEN --file "$spec" --profile github --reason "$reason" 2>/dev/null |
            ${
              cli.gh "auth login" {
                hostname = "github.com";
                with-token = true;
              }
            } 2>/dev/null && ${cli.gh "auth status" { hostname = "github.com"; }} >/dev/null 2>&1; then
            echo "  signed in"
          else
            step "GitHub: approve the code at https://github.com/login/device"
            retry approve "GitHub device code, enter at https://github.com/login/device" '[A-Z0-9]{4}-[A-Z0-9]{4}' ${
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
            }

            step "Storing gh's token as Kagamizo-LLC/github-token"
            ${cli.gh "auth token" { }} | secretspec set GITHUB_TOKEN --file "$spec" --profile github \
              --from-file - --reason "$reason" >/dev/null
          fi

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
            tokenNote=$(relay "Declare and apply: \`github.verifiedDomains.\"$domain\" = \"$token\";\` (TXT $host)")
            echo "  waiting for TXT $host"
            for _ in $(seq 80); do
              if curl -fsS -H 'accept: application/dns-json' "https://cloudflare-dns.com/dns-query?name=$host&type=TXT" |
                jq -e --arg t "$token" 'any(.Answer[]?; .data | contains($t))' >/dev/null; then
                graphql 'mutation($i: ID!) { verifyVerifiableDomain(input: {id: $i}) { domain { isVerified } } }' \
                  "$(jq -n --arg i "$(jq -r .id <<<"$d")" '{i: $i}')" | jq -r '"  verified: \(.data.verifyVerifiableDomain.domain.isVerified)"'
                unrelay "$tokenNote"
                continue 2
              fi
              sleep 30
            done
            echo "  $host did not resolve within 40 minutes; rerun once it does" >&2
            exit 1
          done

          for name in $(jq -r 'with_entries(select(.value.archived | not)) | keys[]' <<<"$repos"); do
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
            if [ "$(jq -r .seed <<<"$r")" = true ]; then
              if ! ${cli.gh "api" { endpoint.shell = "repos/$full"; }} >/dev/null 2>&1; then
                step "Creating $full"
                ${
                  cli.gh "repo create" {
                    name.shell = "$full";
                    private = true;
                    disable-wiki = true;
                  }
                } >/dev/null
              fi
              if ! ${cli.gh "api" { endpoint.shell = "repos/$full/branches/main"; }} >/dev/null 2>&1; then
                step "Seeding $full with $GITHUB_SHA as main"
                ${cli.gh "auth setup-git" { hostname = "github.com"; }}
                git push "https://github.com/$full.git" "$GITHUB_SHA:refs/heads/main"
                ${cli.gh "repo edit" {
                  repository.shell = "$full";
                  default-branch = "main";
                }}
              fi
            fi

            step "$full: visibility, environments, secrets, variables"
            # A transfer settles a while after the repo answers at its new
            # path; until then edits fail with "still in progress".
            for n in $(seq 30); do
              if out=$(${
                cli.gh "repo edit" {
                  repository.shell = "$full";
                  visibility.shell = "$(jq -r .visibility <<<\"$r\")";
                  accept-visibility-change-consequences = true;
                }
              } 2>&1); then
                break
              fi
              if [ "$n" = 30 ] || ! grep -q 'still in progress' <<<"$out"; then
                echo "$out" >&2
                exit 1
              fi
              sleep 10
            done
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

          for name in $(jq -r 'with_entries(select(.value.archived)) | keys[]' <<<"$repos"); do
            full="$org/$name"
            if [ "$(${cli.gh "api" { endpoint.shell = "repos/$full"; }} | jq -r .archived)" != true ]; then
              step "Archiving $full"
              ${cli.gh "repo archive" {
                repository.shell = "$full";
                yes = true;
              }}
            fi
          done

        '';
      };
    };
}
