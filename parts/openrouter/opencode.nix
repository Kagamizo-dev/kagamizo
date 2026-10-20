# OpenCode's config, shared by the host (code.kagamizo.com) and the Orca
# fleet: OpenRouter models only, starting on the default. OpenCode reads the
# key from OPENROUTER_API_KEY, which each consumer's secretspec profile holds.
#
#   nix run .#orca-fleet   Orca, with every agent it launches holding the
#                          fleet's own capped key and this config
{ lib, config, ... }:
let
  cfg = config.openrouter;
in
{
  perSystem =
    { pkgs, config, ... }:
    {
      packages.opencode-config = pkgs.writeText "opencode.json" (
        builtins.toJSON {
          "$schema" = "https://opencode.ai/config.json";
          model = "openrouter/${cfg.defaultModel}";
          enabled_providers = [ "openrouter" ];
          provider.openrouter.models = lib.genAttrs cfg.models (_: { });
        }
      );

      packages.orca-fleet = pkgs.writeShellApplication {
        name = "orca-fleet";
        runtimeInputs = [
          config.packages.secretspec
          config.packages.pass-cli
        ];
        text = ''
          export PROTON_PASS_KEY_PROVIDER=''${PROTON_PASS_KEY_PROVIDER:-fs}
          export OPENCODE_CONFIG=${config.packages.opencode-config}
          exec secretspec run --file ${config.packages.secretspec-toml} --profile agent \
            --reason "orca fleet" -- orca "$@"
        '';
      };
    };
}
