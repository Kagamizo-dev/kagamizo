# The kagamizo repository's own settings, typed in full (the owner's rule
# of 2026-11-06: every setting of every account declared, even the unused
# ones, so every decision is explicit), and its project management from the
# typed backlog: labels for every team, kind of work and status, and an
# issue for every backlog item (modules/agents/backlog.nix), closed when
# the item is done.
#
#   github.repoState = { settings; security; labels; }
#
#   github-state plan    every setting, label and backlog issue against the
#                        live repository; fails on drift or anything
#                        undeclared (./_state, Rust)
#   github-state apply   make the repository match: settings, security,
#                        labels (undeclared ones deleted), backlog issues
#                        (created, relabelled, closed or reopened)
#
# The org's settings and its Projects board need GraphQL, which a cloud
# session cannot reach; ./bootstrap.nix applies those from a runner.
{ lib, config, ... }:
let
  inherit (lib) mkOption types;
  cfg = config.github.repoState;
  backlog = config.agents.backlog;
  teams = lib.attrNames config.agents.charters;
  kinds = lib.attrNames config.agents.lifecycle;
  statuses = [
    "queued"
    "active"
    "done"
  ];
  label = color: description: { inherit color description; };
  enabled = types.enum [
    "enabled"
    "disabled"
  ];
in
{
  options.github.repoState = {
    repo = mkOption {
      type = types.str;
      default = "${config.github.org}/kagamizo";
    };
    settings = {
      hasIssues = mkOption { type = types.bool; };
      hasProjects = mkOption { type = types.bool; };
      hasWiki = mkOption { type = types.bool; };
      hasDiscussions = mkOption { type = types.bool; };
      allowMergeCommit = mkOption { type = types.bool; };
      allowSquashMerge = mkOption { type = types.bool; };
      allowRebaseMerge = mkOption { type = types.bool; };
      allowAutoMerge = mkOption { type = types.bool; };
      deleteBranchOnMerge = mkOption { type = types.bool; };
      allowUpdateBranch = mkOption { type = types.bool; };
      allowForking = mkOption { type = types.bool; };
      webCommitSignoffRequired = mkOption { type = types.bool; };
      squashMergeCommitTitle = mkOption {
        type = types.enum [
          "PR_TITLE"
          "COMMIT_OR_PR_TITLE"
        ];
      };
      squashMergeCommitMessage = mkOption {
        type = types.enum [
          "PR_BODY"
          "COMMIT_MESSAGES"
          "BLANK"
        ];
      };
    };
    security = {
      secretScanning = mkOption { type = enabled; };
      secretScanningPushProtection = mkOption { type = enabled; };
      secretScanningNonProviderPatterns = mkOption { type = enabled; };
      dependabotAlerts = mkOption { type = types.bool; };
      dependabotSecurityUpdates = mkOption { type = enabled; };
    };
    labels = mkOption {
      type = types.attrsOf (
        types.submodule {
          options = {
            color = mkOption { type = types.strMatching "[0-9a-f]{6}"; };
            description = mkOption { type = types.str; };
          };
        }
      );
      description = "Every label the repository has; any other is deleted.";
    };
  };

  config.github.repoState = {
    settings = {
      hasIssues = true;
      # The backlog's board (./bootstrap.nix applies it from a runner).
      hasProjects = true;
      # Papers in Lean are the docs (modules/repo/papers.nix); no wiki.
      hasWiki = false;
      # Teams talk in Matrix; the owner's go is a review, not a thread.
      hasDiscussions = false;
      # History stays linear, so no merge commits. Squash for a change of
      # one commit (its message the PR's title and body, held by
      # commit-lint); rebase for a long-lived branch whose commits are each
      # a change, such as a session's.
      allowMergeCommit = false;
      allowSquashMerge = true;
      allowRebaseMerge = true;
      squashMergeCommitTitle = "PR_TITLE";
      squashMergeCommitMessage = "PR_BODY";
      # Agents' content changes merge on green (modules/governance/changes.nix).
      allowAutoMerge = true;
      deleteBranchOnMerge = true;
      allowUpdateBranch = true;
      # The repository is public: forks are how anyone else proposes.
      allowForking = true;
      webCommitSignoffRequired = false;
    };
    security = {
      # Public repository: GitHub scans it for free, and refuses a push that
      # carries a recognised secret. Values live only in Proton Pass.
      secretScanning = "enabled";
      secretScanningPushProtection = "enabled";
      # Generic patterns (private keys, passwords) need GitHub Advanced
      # Security, which the organization's plan does not include: GitHub
      # accepts the setting and leaves it off.
      secretScanningNonProviderPatterns = "disabled";
      dependabotAlerts = true;
      # Dependabot cannot update Nix pins; upkeep bumps them through PRs.
      dependabotSecurityUpdates = "disabled";
    };
    labels =
      lib.genAttrs (map (t: "team:${t}") teams) (
        _: label "1d76db" "A chartered team (modules/agents/charters.nix)"
      )
      // lib.genAttrs (map (k: "kind:${k}") kinds) (
        _: label "5319e7" "A kind of work, with its lifecycle (modules/agents/charters.nix)"
      )
      // lib.genAttrs (map (s: "status:${s}") statuses) (_: label "0e8a16" "A backlog item's status")
      // {
        backlog = label "fbca04" "An item of the typed backlog (modules/agents/backlog.nix); edit it there, not here";
        bug = label "d73a4a" "Something does not work as declared";
        security = label "b60205" "A finding of the security team or a scanner";
        spend = label "e99695" "Touches money: the owner's decision";
      };
  };

  # The backlog as issues, rendered for github-state.
  options.github.backlogIssues = mkOption {
    type = types.attrsOf types.anything;
    readOnly = true;
    default = lib.mapAttrs (
      id: i:
      let
        team = lib.head (lib.splitString "/" id);
      in
      {
        title = id;
        body = builtins.readFile i.brief;
        labels = [
          "backlog"
          "team:${team}"
          "kind:${i.kind}"
          "status:${i.status}"
        ];
        open = i.status != "done";
      }
    ) backlog;
  };

  config.perSystem =
    { pkgs, ... }:
    let
      declared = pkgs.writeText "github-state.json" (
        builtins.toJSON {
          inherit (cfg)
            repo
            settings
            security
            labels
            ;
          issues = config.github.backlogIssues;
        }
      );
      tool = pkgs.rustPlatform.buildRustPackage {
        pname = "github-state";
        version = "0.1.0";
        src = ./_state;
        cargoLock.lockFile = ./_state/Cargo.lock;
        doCheck = true;
        GITHUB_STATE_DECLARED = declared;
        meta.mainProgram = "github-state";
      };
    in
    {
      packages.github-state = tool;
      checks.github-state = tool;
    };
}
