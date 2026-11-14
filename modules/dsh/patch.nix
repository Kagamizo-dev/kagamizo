# The patch entries both the host (../hetzner/_harness.nix) and a headless
# session (./dispatch.nix) render by the same declarations: a provider
# configuration under the pi-ai adapter plugin, the default model, the
# sandbox policy, tools, and (for the host) the agent-team plugins. Call
# `config.dsh.renderPatch` with the shared arguments and merge in what
# only the caller knows.
#
#   config.dsh.renderPatch { providers = { ... }; defaultModel = "...";
#                            workspaceRoot = "..."; extra = []; }
#
# returns a derivation (writeText) of the JSON patch file.
#
# Available in perSystem config (so host.nix uses it inside withSystem).
{
  lib,
  ...
}:
let
  inherit (builtins) toJSON;

  # Pi-ai adapter plugin id, declared in `@deepseek-ai/dsh-base/cordis.patch.yml`.
  llmAdapterId = "llm-pi-ai";
in
{
  perSystem =
    { pkgs, ... }:
    {
      options.dsh.renderPatch = lib.mkOption {
        type = lib.types.functionTo lib.types.raw;
        readOnly = true;
        description = ''
          Render a dsh patch JSON file from provider and model declarations.
          Takes { providers; defaultModel; workspaceRoot; extra ? []; }.
          Returns a derivation (writeText) of the JSON patch.
        '';
      };

      config.dsh.renderPatch =
        {
          providers,
          defaultModel,
          workspaceRoot,
          extra ? [ ],
        }:
        pkgs.writeText "kagamizo.patch.json" (
          toJSON (
            lib.filter (x: x != null) [
              # Provider routes: the pi-ai adapter plugin must match the id
              # the adapter registers itself under (llm-pi-ai).
              {
                id = llmAdapterId;
                config.providers = providers;
              }

              # The agent's default model, expressed as provider + model.
              {
                id = "agent-default-model";
                config = {
                  provider = builtins.head (lib.attrNames providers);
                  model = defaultModel;
                };
              }

              # The sandbox policy: what the shell in the harness may write.
              {
                id = "sandbox-policy";
                config = {
                  mode = "workspace-write";
                  inherit workspaceRoot;
                };
              }

              # The shell tool (tool-bash) is enabled by default; the dispatch
              # caller may pass extra that disables it.
              {
                id = "tool-bash";
                disabled = false;
              }

              # The dispatch session disables web-search-deepseek and
              # web-deepseek-api; the host does too (no DeepSeek-official key).
              {
                id = "web-search-deepseek";
                disabled = true;
              }
              {
                id = "web-deepseek-api";
                disabled = true;
              }
            ]
            ++ extra
          )
        );
    };
}
