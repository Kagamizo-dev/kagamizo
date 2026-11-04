# Who may merge what, typed (the self-update loop, the owner's plan of
# 2026-11-04): every path of the repository falls in a change class, and a
# class says who merges a request that touches it.
#
#   governance.changeClasses.<class> = { merge; paths; why; }
#       merge = "agent"   agents merge it themselves once the checks pass
#               "owner"   the owner approves it in the request (one tap)
#               "never"   never from an agent's branch (agents/*)
#       paths   globs (`*` in a segment, `**` across them); the most
#               restrictive matching class wins; a path matching none is
#               `code` (owner)
#
#   nix run .#changes -- classify PATH...
#   nix run .#changes -- decide --branch B [--approved] PATH...
#       the Rust tool (./_changes) CI runs on every pull request: an
#       agent's request merges only as the classes allow
#
# checks.governance-changes: Lean (./_lean/Changes.lean) proves a request
# an agent may merge is never one that is refused and that adding any
# path never widens the agents' leave; the rendered table has exactly one
# agents' class and the three never classes; the tool's own tests run.
{ lib, config, ... }:
let
  inherit (lib) mkOption types;
  cfg = config.governance.changeClasses;
  # The owner's own GitHub account: the one whose approval merges an owner
  # class (the organization's parent, ../github/account.nix).
  owner = config.accounts.held.${config.github.account}.signup.parent;
  q = builtins.toJSON;
  order = {
    agent = 0;
    owner = 1;
    never = 2;
  };
  class = types.submodule {
    options = {
      merge = mkOption { type = types.enum (lib.attrNames order); };
      paths = mkOption {
        type = types.nonEmptyListOf (types.strMatching "[A-Za-z0-9_.*/-]+");
      };
      why = mkOption { type = types.str; };
    };
  };
  table = lib.concatStrings (
    lib.concatLists (lib.mapAttrsToList (n: c: map (p: "${n}\t${c.merge}\t${p}\n") c.paths) cfg)
  );
  rendered = ''
    namespace Kagamizo.Changes

    /-- Every class, rendered by modules/governance/changes.nix. -/
    def classes : List Class := [
    ${lib.concatStringsSep ",\n" (
      lib.mapAttrsToList (n: c: "  { name := ${q n}, merge := .${c.merge} }") cfg
    )}
    ]

    /-- Exactly one class is the agents' own. -/
    theorem one_agent_class : (classes.filter (·.merge == .agent)).length = 1 := by decide

    /-- Infrastructure, secrets and spending are never an agent's. -/
    theorem never_classes :
        ["infra", "secret", "spend"].all (fun n => classes.any fun c => c.name == n && c.merge == .never) = true := by
      decide

    /-- A request of the agents' class alone is theirs to merge; one that
    adds any never class is refused. -/
    example : agentMayMerge (classes.filter (·.merge == .agent)) = true := by decide
    example : refused (classes.filter (·.merge == .never)) = true := by decide

    end Kagamizo.Changes
  '';
in
{
  options.governance.changeClasses = mkOption {
    type = types.attrsOf class;
    default = { };
  };

  config = {
    governance.changeClasses = {
      content = {
        merge = "agent";
        paths = [
          "modules/twin/_items/**"
          "modules/site/_copy/**"
          "modules/project/_data/**"
          "modules/scout/_data/**"
        ];
        why = "the twin's items, the pages' copy and the project's data (epics, decisions, gaps) and scout's candidates: declarations the checks fully decide";
      };
      code = {
        merge = "owner";
        paths = [
          "**/*.nix"
          "**/*.rs"
          "**/*.lean"
          "**/*.py"
          "**/Cargo.*"
          "**/*.cedar"
        ];
        why = "every module, Rust crate, Lean proof and script (and whatever matches no class)";
      };
      tool = {
        merge = "owner";
        paths = [
          "modules/catalog/**"
          "flake.nix"
          "flake.lock"
        ];
        why = "what is pinned: catalogs and inputs";
      };
      mod = {
        merge = "owner";
        paths = [ "modules/twin/_mod/**" ];
        why = "the Minecraft mod: Java shim and Rust core";
      };
      page-design = {
        merge = "owner";
        paths = [
          "modules/site/*.nix"
          "modules/site/_design/**"
        ];
        why = "the pages' layout and design system";
      };
      infra = {
        merge = "never";
        paths = [
          "modules/cloudflare/**"
          "modules/hetzner/**"
          "modules/ci/**"
          "modules/github/**"
          "modules/statestore/**"
          ".github/**"
        ];
        why = "what applies to Cloudflare, Hetzner, GitHub and CI";
      };
      secret = {
        merge = "never";
        paths = [
          "secretspec.toml"
          "modules/*/secrets.nix"
          "modules/proton/**"
          "modules/_lib/secret.nix"
          "modules/operations/**"
        ];
        why = "what names a secret, a vault or an agent token";
      };
      spend = {
        merge = "never";
        paths = [
          "modules/mercury/**"
          "modules/openrouter/**"
          "modules/*/card.nix"
          "modules/*/budget.nix"
          "modules/agents/tiers.nix"
          "modules/accounts/**"
        ];
        why = "cards, caps, budgets, tiers and the accounts' plans";
      };
    };

    perSystem =
      { pkgs, ... }:
      let
        tableFile = pkgs.writeText "change-classes.tsv" table;
        changes = pkgs.rustPlatform.buildRustPackage {
          pname = "changes";
          version = "0.1.0";
          src = ./_changes;
          cargoLock.lockFile = ./_changes/Cargo.lock;
          CHANGE_CLASSES = tableFile;
          doCheck = true;
          meta.mainProgram = "changes";
        };
        # What CI runs on a pull request: the request's paths from its commit
        # range, its branch, and whether the owner (the organization's parent
        # account) approved it, then `changes decide`.
        ci = pkgs.writeShellApplication {
          name = "changes-ci";
          runtimeInputs = [
            changes
            pkgs.git
            pkgs.gh
            pkgs.jq
            pkgs.coreutils
          ];
          text = ''
            : "''${RANGE:?}" "''${BRANCH:?}" "''${REPO:?}"
            mapfile -t paths < <(git diff --name-only "$RANGE")
            approved=()
            if [ -n "''${PR:-}" ] && [ -n "''${GH_TOKEN:-}" ]; then
              if gh api "repos/$REPO/pulls/$PR/reviews" --paginate |
                jq -e --arg o ${lib.escapeShellArg owner} 'map(select(.state == "APPROVED" and .user.login == $o)) | length > 0' >/dev/null; then
                approved=(--approved)
              fi
            fi
            changes classify "''${paths[@]}"
            changes decide --branch "$BRANCH" "''${approved[@]}" "''${paths[@]}"
          '';
        };
      in
      {
        packages.changes = changes;
        packages.changes-ci = ci;
        checks.governance-changes =
          pkgs.runCommand "governance-changes"
            {
              nativeBuildInputs = [ pkgs.lean4 ];
              facts = rendered;
              passAsFile = [ "facts" ];
            }
            ''
              cat ${./_lean/Changes.lean} "$factsPath" > Check.lean
              lean Check.lean
              # The tool agrees with the table on a sample of each class.
              ${lib.getExe changes} classify modules/twin/_items/x.json modules/agents/tiers.nix modules/cloudflare/infra.nix | tee classes
              grep -q '^request	never$' classes
              touch $out
            '';
      };
  };
}
