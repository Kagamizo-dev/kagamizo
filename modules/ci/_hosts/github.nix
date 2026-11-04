# GitHub Actions, rendered from ci.workflows (../default.nix). The actions
# a job uses are pinned by commit here and nowhere else; ci.hosts.forgejo
# reuses this renderer, since Forgejo Actions reads the same syntax.
{ lib, ... }:
let
  actions = {
    checkout = "actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5"; # v4.3.1
    nix = "cachix/install-nix-action@2126ae7fc54c9df00dd18f7f18754393182c73cd"; # v31.9.1
    upload = "actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02"; # v4.6.2
  };
  runners = {
    linux-x86_64 = "ubuntu-latest";
    # GitHub's x86_64 Linux runners have KVM.
    linux-x86_64-kvm = "ubuntu-latest";
    linux-aarch64 = "ubuntu-24.04-arm";
  };
  contexts = {
    commit = "\${{ github.sha }}";
    repository = "\${{ github.repository }}";
    branch = "\${{ github.head_ref || github.ref_name }}";
    pull-request = "\${{ github.event.pull_request.number }}";
    token = "\${{ github.token }}";
    # PRs (and their reviews): every commit the PR adds. Pushes: every
    # commit pushed; a new branch (before is all zeros) checks its whole
    # history.
    commit-range = lib.concatStringsSep " " [
      "\${{ (github.event_name == 'pull_request' || github.event_name == 'pull_request_review')"
      "&& format('{0}..{1}', github.event.pull_request.base.sha, github.event.pull_request.head.sha)"
      "|| (github.event.before == '0000000000000000000000000000000000000000' && github.sha"
      "|| format('{0}..{1}', github.event.before, github.sha)) }}"
    ];
  };
  envValue =
    v:
    if builtins.isString v then
      v
    else if v.secret != null then
      "\${{ secrets.${v.secret} }}"
    else if v.context != null then
      contexts.${v.context}
    else
      throw "ci: an env value names neither a context nor a secret";

  on =
    t:
    lib.optionalAttrs (t.push != null) {
      push =
        lib.optionalAttrs (t.push.branches != null) { inherit (t.push) branches; }
        // lib.optionalAttrs (t.push.branchesIgnore != null) { branches-ignore = t.push.branchesIgnore; };
    }
    // lib.optionalAttrs t.pullRequest { pull_request = { }; }
    // lib.optionalAttrs t.pullRequestReview { pull_request_review.types = [ "submitted" ]; }
    // lib.optionalAttrs t.call { workflow_call = { }; }
    // lib.optionalAttrs t.manual { workflow_dispatch = { }; }
    // lib.optionalAttrs (t.schedule != [ ]) { schedule = map (c: { cron = c; }) t.schedule; };

  step =
    s:
    lib.optionalAttrs (s.name != null) { inherit (s) name; }
    // lib.optionalAttrs s.always { "if" = "always()"; }
    // (
      # The flake's own pinned pass-cli (modules/proton/tools.nix), not an
      # action: protonpass/install-cli-action's pinned commit shipped no
      # dist/index.js (2026-11-01), and the flake pins the same binary.
      if s.passCli != null then
        {
          name = "pass-cli ${s.passCli} (the flake's)";
          run = "nix profile install .#pass-cli && pass-cli --version";
        }
      else if s.artifact != null then
        {
          uses = actions.upload;
          "with" = {
            inherit (s.artifact) name path;
            if-no-files-found = "ignore";
          };
        }
      else
        {
          inherit (s) run;
        }
        // lib.optionalAttrs (s.env != { }) { env = lib.mapAttrs (_: envValue) s.env; }
    );

  job =
    j:
    {
      inherit (j) name;
      runs-on = runners.${j.runner};
      timeout-minutes = j.timeoutMinutes;
      inherit (j) permissions;
      steps = [
        {
          uses = actions.checkout;
          "with" = {
            persist-credentials = false;
          }
          // lib.optionalAttrs (j.history == "full") { fetch-depth = 0; };
        }
      ]
      # VM tests need room: the runner's preinstalled toolchains go, in the
      # background, so the job does not wait the minute and a half the
      # deletion takes (it took half the checks job, 2026-11-04); the
      # runner keeps it running until the job ends.
      ++ lib.optional (j.runner == "linux-x86_64-kvm") {
        name = "Free disk space (in the background)";
        run = "(sudo rm -rf /usr/share/dotnet /usr/local/lib/android /opt/ghc /opt/hostedtoolcache/CodeQL >/dev/null 2>&1 &)";
      }
      ++ [
        {
          uses = actions.nix;
          "with".extra_nix_config = "accept-flake-config = true";
        }
      ]
      ++ map step j.steps;
    }
    // lib.optionalAttrs (j.needs != [ ]) { inherit (j) needs; };

  render =
    pkgs: workflows:
    lib.mapAttrs' (
      w: wf:
      let
        yaml = (pkgs.formats.yaml { }).generate "${w}.yml" (
          {
            name = w;
            on = on wf.on;
            permissions = { };
            jobs = lib.mapAttrs (_: job) wf.jobs;
          }
          // lib.optionalAttrs wf.cancelSuperseded {
            concurrency = {
              group = "\${{ github.workflow }}-\${{ github.ref }}";
              cancel-in-progress = true;
            };
          }
        );
      in
      lib.nameValuePair "${w}.yml" (
        pkgs.runCommand "${w}.yml" { } ''
          {
            echo "# Generated by modules/ci from ci.workflows.${w}; do not edit."
            echo "# ${lib.replaceStrings [ "\n" ] [ "\n# " ] wf.description}"
            cat ${yaml}
          } > $out
        ''
      )
    ) workflows;
in
{
  ci.hosts.github = {
    enable = true;
    dir = ".github/workflows";
    inherit render;
  };
  _module.args.ciGithubRender = render;
}
