# Claude session setup as code: the pinned session tools and the typed
# network allowlist rendered to the paste-ready form.
{
  perSystem =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    let
      env = lib.evalModules { modules = [ ./_environment.nix ]; };
      enabled = lib.filter (g: g.enable) (lib.attrValues env.config.network.allow);
      hosts = lib.unique (lib.sort lib.lessThan (lib.concatMap (g: g.hosts) enabled));

      # One domain per line, exactly what the Allowed domains field takes. Pair
      # it with the "include default list" box set to network.includeDefaults.
      allowed-domains = pkgs.writeText "allowed-domains.txt" (lib.concatLines hosts);
      # Put on PATH by .claude/hooks/session-start.sh in cloud sessions.
      session-tools = pkgs.symlinkJoin {
        name = "session-tools";
        paths = with config.packages; [
          pass-cli
          secretspec
          cf
          cloudflare-login
          bootstrap
          infra
          registrar
          proton
          commit-lint
        ];
      };
    in
    {
      packages = {
        inherit session-tools;
        claude-allowed-domains = allowed-domains;
      };
      # Type-checks the allowlist and builds the pinned session tools.
      checks = {
        inherit session-tools;
        claude-allowed-domains = allowed-domains;
      };
    };
}
