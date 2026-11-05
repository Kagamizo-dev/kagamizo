# `dispatch <team>/<topic> <task-file>` — run a DeepSeek Harness headless
# session on a dedicated agents/<team>/<topic> branch.
#
# Usage:
#
#   nix run .#dispatch -- upkeep/audit task.json
#
# creates or reuses a git worktree at
# $XDG_STATE_HOME/kagamizo/dispatch/<team>-<topic> on branch
# agents/<team>/<topic>, renders a dsh patch for the team (OpenRouter
# only, sandboxed to the worktree, tool-bash enabled, web-search and
# web-api disabled), runs the task under `secretspec run --profile agent`,
# and writes the JSON event stream to
# <state>/log/<team>-<topic>.jsonl, printing the `final` event's text at
# the end.
#
# The team must be a declared governance agent (governance.agents.<team>)
# whose harness is "dsh".
{
  lib,
  config,
  ...
}:
let
  top = config;
  cfg = config.governance;

  piAiAdapterId = "llm-pi-ai";
in
{
  perSystem =
    { pkgs, config, ... }:
    let
      agents = lib.attrNames (lib.filterAttrs (_: a: a.harness == "dsh") cfg.agents);
      agentNames = lib.concatStringsSep " " agents;

      # The model entry shape dsh expects: { id, name }.
      modelEntry = id: {
        inherit id;
        name = id;
      };

      # Patch snippets rendered at build time from the declarations, for
      # providers and tools that do not depend on the runtime worktree path.
      openrouterProviders = pkgs.writeText "openrouter-providers.json" (
        builtins.toJSON {
          openrouter = {
            displayName = "OpenRouter (Jingzo's agent key)";
            api = "openai-completions";
            baseURL = "https://openrouter.ai/api/v1";
            apiKeyEnv = "OPENROUTER_API_KEY";
            models = map modelEntry top.openrouter.models;
            compat.thinkingFormat = "openrouter";
          };
        }
      );

      # Every dsh agent's declared model, as JSON for runtime lookup.
      agentModelsJson = pkgs.writeText "agent-models.json" (
        builtins.toJSON (
          lib.mapAttrs (_: a: { inherit (a) model; })
          (lib.filterAttrs (_: a: a.harness == "dsh") cfg.agents)
        )
      );
    in
    {
      packages.dispatch = pkgs.writeShellApplication {
        name = "dispatch";
        runtimeInputs = [
          pkgs.git
          pkgs.coreutils
          pkgs.jq
          config.packages.secretspec
          config.packages.dsh
        ];
        text = ''
          usage="usage: dispatch <team>/<topic> <task-file>"
          arg=''${1:?$usage}
          task=''${2:?$usage}

          team=''${arg%%/*}
          topic=''${arg#*/}
          [ "$team" != "$topic" ] || { echo "dispatch: usage: <team>/<topic>"; exit 2; }

          # Check the team is a declared dsh agent.
          IFS=' ' read -ra agents <<< "${agentNames}"
          found=0
          for a in "''${agents[@]}"; do
            [ "$a" = "$team" ] && { found=1; break; }
          done
          [ "$found" = 1 ] || {
            echo "dispatch: no dsh agent ''${team}; declared: ${agentNames}" >&2
            exit 2
          }

          state=''${XDG_STATE_HOME:-''${HOME}/.local/state}/kagamizo/dispatch
          worktree="$state/$team-$topic"
          logdir="$state/log"
          branch="agents/$team/$topic"

          mkdir -p "$state" "$logdir"

          # Create or reuse the worktree.
          if [ -d "$worktree/.git" ]; then
            git worktree remove "$worktree" 2>/dev/null || true
          fi
          if ! git worktree add "$worktree" "$branch" 2>/dev/null; then
            git worktree add -B "$branch" "$worktree" HEAD
          fi

          # The team's model from the Nix declarations (store path).
          model=$(jq -r --arg t "$team" '.[$t].model // empty' "${agentModelsJson}")
          [ -n "$model" ] || { echo "dispatch: no model for team $team" >&2; exit 2; }

          # Render the patch at runtime with the worktree path.
          # providers and piAiAdapterId come from store paths, not inline JSON.
          patch=$(
            jq -n \
              --arg piAiAdapterId "${piAiAdapterId}" \
              --arg model "$model" \
              --arg worktree "$worktree" \
              --slurpfile providers "${openrouterProviders}" \
              '[
                { id: $piAiAdapterId, config: { providers: $providers[0] } },
                { id: "agent-default-model", config: { provider: "openrouter", model: $model } },
                { id: "sandbox-policy", config: { mode: "workspace-write", workspaceRoot: $worktree } },
                { id: "tool-bash", disabled: false },
                { id: "web-search-deepseek", disabled: true },
                { id: "web-deepseek-api", disabled: true }
              ]'
          )

          # Set git authorship.
          export GIT_AUTHOR_NAME="$team (dsh)"
          export GIT_AUTHOR_EMAIL="agents@jingzo.org"
          export GIT_COMMITTER_NAME="$team (dsh)"
          export GIT_COMMITTER_EMAIL="agents@jingzo.org"
          export GIT_CONFIG_NOSYSTEM=1

          # Run the task.
          DSH_HOME="$state" \
          secretspec run --file ${config.packages.secretspec-toml} --profile agent \
            --reason "dispatch: $team/$topic" -- \
            ${lib.getExe config.packages.dsh} --profile headless \
              --patch <(printf '%s' "$patch") --json < "$task" \
          > "$logdir/$team-$topic.jsonl" 2>&1 || true

          # Print the final event's text.
          jq -r 'select(.type == "final") | .text // .' "$logdir/$team-$topic.jsonl" 2>/dev/null || \
            echo "(no final event in $logdir/$team-$topic.jsonl)"

          # Report the worktree state.
          echo "---"
          git -C "$worktree" status --short 2>/dev/null || true
          echo "---"
          git -C "$worktree" log --oneline "$branch" --not --remotes 2>/dev/null || true
        '';
      };
    };
}