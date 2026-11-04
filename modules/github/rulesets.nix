# Branch rulesets, typed and applied by `github-bootstrap` (./bootstrap.nix):
# what keeps the self-update loop honest on GitHub's side
# (modules/governance/changes.nix). The agents' App is never a bypass
# actor, so these are the only ways it can change the repository.
#
#   github.rulesets.<repo>.<name> = {
#     include; exclude;          # ref patterns (refs/heads/..., ~ALL, ~DEFAULT_BRANCH)
#     pullRequest;               # changes land only through a pull request
#     requiredChecks;            # the workflow jobs that must pass first
#     restrict;                  # creation | update | deletion: only bypass actors
#     bypassAdmins;              # repository admins (the owner) bypass it
#   }
{ lib, config, ... }:
let
  inherit (lib) mkOption types;
  cfg = config.github;
  ruleset = types.submodule {
    options = {
      include = mkOption {
        type = types.nonEmptyListOf types.str;
      };
      exclude = mkOption {
        type = types.listOf types.str;
        default = [ ];
      };
      pullRequest = mkOption {
        type = types.bool;
        default = false;
      };
      requiredChecks = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Job names (ci.workflows.<w>.jobs.<j>.name) that must pass.";
      };
      restrict = mkOption {
        type = types.listOf (
          types.enum [
            "creation"
            "update"
            "deletion"
          ]
        );
        default = [ ];
      };
      bypassAdmins = mkOption {
        type = types.bool;
        default = true;
      };
      why = mkOption { type = types.str; };
    };
  };
  # Every job name declared in CI, so a required check names a real one.
  jobNames = lib.concatLists (
    lib.mapAttrsToList (_: w: lib.mapAttrsToList (_: j: j.name) w.jobs) config.ci.workflows
  );
  # GitHub's rulesets API shape (REST: repos/{owner}/{repo}/rulesets).
  render =
    name: r:
    assert lib.assertMsg (lib.all (c: lib.elem c jobNames) r.requiredChecks)
      "github.rulesets: ${name} requires a check no workflow job is named: ${lib.concatStringsSep ", " (lib.subtractLists jobNames r.requiredChecks)}";
    {
      inherit name;
      target = "branch";
      enforcement = "active";
      bypass_actors = lib.optional r.bypassAdmins {
        actor_id = 5; # the repository's admin role
        actor_type = "RepositoryRole";
        bypass_mode = "always";
      };
      conditions.ref_name = {
        inherit (r) include exclude;
      };
      rules =
        map (t: { type = t; }) r.restrict
        ++ lib.optional r.pullRequest {
          type = "pull_request";
          parameters = {
            required_approving_review_count = 0;
            dismiss_stale_reviews_on_push = true;
            require_code_owner_review = false;
            require_last_push_approval = false;
            required_review_thread_resolution = false;
            allowed_merge_methods = [ "squash" ];
          };
        }
        ++ lib.optional (r.requiredChecks != [ ]) {
          type = "required_status_checks";
          parameters = {
            strict_required_status_checks_policy = true;
            required_status_checks = map (c: { context = c; }) r.requiredChecks;
          };
        };
    };
in
{
  options.github = {
    rulesets = mkOption {
      type = types.attrsOf (types.attrsOf ruleset);
      default = { };
      description = "repo -> name -> ruleset.";
    };
    rulesetsJson = mkOption {
      type = types.attrsOf (types.listOf types.attrs);
      readOnly = true;
      description = "repo -> the rulesets as GitHub's API takes them (./bootstrap.nix).";
    };
  };

  config.github = {
    rulesets.kagamizo = {
      # main moves only through a pull request that the gate and the checks
      # passed; the owner (admin) may still push it directly.
      main-gated = {
        include = [ "~DEFAULT_BRANCH" ];
        pullRequest = true;
        requiredChecks = [
          "change classes"
          "flake check (format, lint, Lean, VM tests)"
          "commit messages (Sentry conventions)"
          "lint workflows (actionlint, zizmor)"
        ];
        why = "an agent's request merges only as its change classes allow";
      };
      # Every other branch is the owner's: the agents' App may create,
      # update or delete only agents/*.
      agents-branches = {
        include = [ "~ALL" ];
        exclude = [
          "refs/heads/agents/**"
          "~DEFAULT_BRANCH"
        ];
        restrict = [
          "creation"
          "update"
          "deletion"
        ];
        why = "an agent writes only its own branches";
      };
    };
    rulesetsJson = lib.mapAttrs (_: rs: lib.mapAttrsToList render rs) cfg.rulesets;
  };
}
