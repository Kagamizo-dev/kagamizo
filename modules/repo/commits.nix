# Commit messages follow Sentry's engineering practices
# (develop.sentry.dev/engineering-practices/commit-messages), which build on
# Conventional Commits:
#
#   <type>(<scope>): <Subject>
#
#   <body: what and why>
#
#   <footer: Fixes GH-123, BREAKING CHANGE: ..., trailers>
#
# `commit-lint` enforces it. A flake check cannot see git history (flakes
# evaluate a copy of the tree without .git), so it runs as a commit-msg hook
# (installed in cloud sessions by .claude/hooks/session-start.sh) and in CI on
# every pushed or proposed range; `nix flake check` runs its self-test.
#
#   commit-lint <range>                 check every commit in a range
#   commit-lint --message-file <file>   check one message (the commit-msg hook)
#   commit-lint --install-hook          install the commit-msg hook
{ lib, ... }:
let
  # Sentry's types and what each is for.
  types = {
    build = "Build system or external dependencies";
    ci = "CI configuration and scripts";
    docs = "Documentation only";
    feat = "A new feature";
    fix = "A bug fix";
    perf = "A change that improves performance";
    ref = "Neither fixes a bug nor adds a feature (refactor)";
    chore = "Housekeeping that changes no behavior";
    style = "Formatting, whitespace; no meaning changes";
    test = "Adding or correcting tests";
    meta = "Repository metadata: README, templates, config";
    license = "Changes to licenses";
    revert = "Reverts a commit: revert: <header>, body 'This reverts commit <sha>.'";
  };

  subjectMax = 70;
  lineMax = 100;

  # Commits up to and including these predate the convention and are not
  # checked; everything after them is. The second is the tip of the old beta
  # branch, merged into main with its history.
  baselines = [
    "66993b37261075ea1426b75afde604556d4c7375"
    "98bd2d2890bd9e475bcd9f03cf8b58c34cfe53af"
  ];

  # A revert's subject is the reverted commit's header, so it is exempt from
  # the capital letter. Brackets instead of backslashes survive awk -v.
  header = lib.concatStrings [
    "^(revert: .*[^.]|"
    "(${lib.concatStringsSep "|" (lib.attrNames (removeAttrs types [ "revert" ]))})"
    "([(][a-z0-9][a-z0-9._/-]*[)])?!?: [A-Z].*[^.])$"
  ];
in
{
  perSystem =
    { pkgs, ... }:
    let
      commit-lint = pkgs.writeShellApplication {
        name = "commit-lint";
        runtimeInputs = [
          pkgs.git
          pkgs.gawk
        ];
        text = ''
          usage="usage: commit-lint <range> | --message-file <file> | --install-hook"

          # Prints one line per problem with the message on stdin; silent when clean.
          problems() {
            awk -v re=${lib.escapeShellArg header} -v smax=${toString subjectMax} -v lmax=${toString lineMax} '
              # git comments (commit-msg hook input) are not part of the message
              /^#/ { next }
              { n++; line[n] = $0 }
              END {
                while (n > 0 && line[n] == "") n--
                if (n == 0) { print "empty message"; exit }
                h = line[1]
                if (h ~ /^(Merge |fixup! |squash! |amend! )/) exit
                if (h !~ re)
                  print "header must be \"<type>(<scope>): <Capitalized subject>\" with no trailing period; types: ${lib.concatStringsSep " " (lib.attrNames types)}"
                if (length(h) > smax) print "header is " length(h) " characters; at most " smax
                if (n > 1 && line[2] != "") print "line 2 must be blank (separates header from body)"
                for (i = 2; i <= n; i++)
                  if (length(line[i]) > lmax) print "line " i " is " length(line[i]) " characters; at most " lmax
              }'
          }

          case "''${1:?$usage}" in
            --message-file)
              out=$(problems < "''${2:?$usage}")
              if [ -n "$out" ]; then
                printf 'commit message rejected (see modules/repo/commits.nix):\n%s\n' "$out" >&2
                exit 1
              fi
              ;;
            --install-hook)
              hook="$(git rev-parse --git-path hooks)/commit-msg"
              # shellcheck disable=SC2016 # $1 is for the hook, not this script
              printf '#!/bin/sh\nexec %s --message-file "$1"\n' "$(readlink -f "$0")" > "$hook"
              chmod +x "$hook"
              echo "installed $hook"
              ;;
            -*)
              echo "$usage" >&2
              exit 2
              ;;
            *)
              status=0
              # Only commits after the baselines; skip one when it is not in this history.
              exclude=()
              for b in ${lib.concatStringsSep " " baselines}; do
                if git cat-file -e "$b^{commit}" 2>/dev/null; then exclude+=("^$b"); fi
              done
              for sha in $(git rev-list --no-merges "$1" "''${exclude[@]}"); do
                out=$(git log -1 --format=%B "$sha" | problems)
                if [ -n "$out" ]; then
                  printf '%s %s\n%s\n\n' "$(git rev-parse --short "$sha")" "$(git log -1 --format=%s "$sha")" "$(awk '{ print "  - " $0 }' <<<"$out")"
                  status=1
                fi
              done
              exit "$status"
              ;;
          esac
        '';
      };

      # Messages the rules must accept and reject.
      good = {
        plain = "feat(identity): Add the QSearch domain";
        body = "fix: Count renewals in the monthly budget\n\nRenewals were left out of the total.\n\nFixes GH-12\nCo-Authored-By: A <a@example.com>";
        breaking = "ref(cloudflare)!: Rename the zone layer";
        revert = "revert: feat(identity): Add the QSearch domain\n\nThis reverts commit abc1234.";
      };
      bad = {
        no-type = "Add the QSearch domain";
        unknown-type = "refactor: Rename the zone layer";
        lowercase = "feat: add the QSearch domain";
        period = "feat: Add the QSearch domain.";
        long-header = "feat: ${lib.concatStrings (lib.replicate 70 "x")}";
        no-blank = "feat: Add it\nbody right away";
        long-line = "feat: Add it\n\n${lib.concatStrings (lib.replicate 101 "x")}";
      };
      cases =
        expect: msgs:
        lib.concatStrings (
          lib.mapAttrsToList (name: msg: ''
            printf '%s' ${lib.escapeShellArg msg} > msg
            if commit-lint --message-file msg 2>/dev/null; then got=accept; else got=reject; fi
            if [ "$got" != ${expect} ]; then echo "${name}: expected ${expect}, got $got"; fail=1; fi
          '') msgs
        );
    in
    {
      packages = { inherit commit-lint; };
      checks.commit-lint =
        pkgs.runCommand "commit-lint-self-test" { nativeBuildInputs = [ commit-lint ]; }
          ''
            fail=0
            ${cases "accept" good}
            ${cases "reject" bad}
            [ "$fail" = 0 ]
            touch $out
          '';
    };
}
