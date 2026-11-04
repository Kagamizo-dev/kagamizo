# The workflows, for every host modules/ci renders.
{
  ci.workflows = {
    # The merge gate of the self-update loop (modules/governance/changes.nix):
    # on every pull request, and again when a review lands, decide the
    # request by its classes. Required on main (modules/github), so an
    # agent's request merges only as the classes allow.
    change-class = {
      description = "Which classes a pull request touches, and whether it may merge as it stands (the agents' classes alone, or with the owner's approval).";
      on = {
        pullRequest = true;
        pullRequestReview = true;
      };
      jobs.decide = {
        name = "change classes";
        runner = "linux-x86_64";
        timeoutMinutes = 10;
        history = "full";
        permissions = {
          contents = "read";
          pull-requests = "read";
        };
        steps = [
          {
            name = "changes decide";
            env = {
              RANGE.context = "commit-range";
              BRANCH.context = "branch";
              PR.context = "pull-request";
              REPO.context = "repository";
              GH_TOKEN.context = "token";
            };
            run = "nix run .#changes-ci";
          }
        ];
      };
    };

    checks = {
      description = "Every flake check (formats, lints, Lean, Cedar, the NixOS VM tests), the workflow files and the commit messages.";
      on = {
        # main runs these through the yoga-c940 pipeline. Pushes only: a
        # pull request's commits are pushes already, and its checks are the
        # commit's, so a pull_request trigger ran everything twice.
        push.branchesIgnore = [ "main" ];
        call = true;
      };
      jobs = {
        flake = {
          name = "flake check (format, lint, Lean, VM tests)";
          runner = "linux-x86_64-kvm";
          timeoutMinutes = 90;
          steps = [
            {
              name = "nix flake check";
              run = "nix flake check --print-build-logs";
            }
            {
              name = "Upload VM test screenshots";
              always = true;
              artifact = {
                name = "vm-test-screenshots";
                path = "result*/*.png";
              };
            }
          ];
        };
        workflows = {
          name = "lint workflows (actionlint, zizmor)";
          runner = "linux-x86_64";
          timeoutMinutes = 10;
          steps = [
            { run = "nix run nixpkgs#actionlint"; }
            { run = "nix run nixpkgs#zizmor -- --offline .github/workflows"; }
          ];
        };
        commits = {
          name = "commit messages (Sentry conventions)";
          runner = "linux-x86_64";
          timeoutMinutes = 10;
          history = "full";
          steps = [
            {
              name = "commit-lint";
              env.RANGE.context = "commit-range";
              run = ''nix run .#commit-lint -- "$RANGE"'';
            }
          ];
        };
      };
    };

    # Hetzner's OpenAPI spec has no versions (modules/catalog/sources.nix):
    # re-read it weekly, and fail, naming it, when it moved, so the catalog
    # is refreshed on purpose rather than breaking a build.
    spec-drift = {
      description = "Weekly: whether an unversioned upstream spec moved since its catalog was read.";
      on = {
        schedule = [ "17 6 * * 1" ];
        manual = true;
      };
      cancelSuperseded = false;
      jobs.hetzner-api = {
        name = "Hetzner Cloud's OpenAPI spec";
        runner = "linux-x86_64";
        timeoutMinutes = 15;
        steps = [
          {
            name = "Re-read the spec";
            run = "nix run .#hetzner-api-update";
          }
          {
            name = "Fail if the catalog moved";
            run = "git diff --exit-code -- modules/catalog/_json/hetzner-api.json";
          }
        ];
      };
    };
  };
}
