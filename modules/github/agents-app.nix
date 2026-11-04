# The agents' GitHub identity: a GitHub App on the organization, never a
# person's token, so the rulesets (./rulesets.nix) hold against it and its
# work is signed as the App. Made by GitHub's manifest flow, which needs
# no console paste: the owner opens the prepared page (`github-app-manifest`,
# sent as a file card), clicks Create, and GitHub sends the new App's
# private key to jingzo-host (`/_github/app` on chat.<zone>, behind Access:
# ../hetzner/_github-app.nix), which stores it in the host's state vault.
# The App's id is read back from the key (GET /app) and its installation
# found (GET /app/installations), so nothing is typed anywhere.
#
#   github.agentsApp = { name; permissions; item; }
#   nix build .#github-app-manifest     the page the owner opens
#   nix run .#github-app-token -- OUT   an installation token (one hour)
#                                       into OUT, mode 600: what the bots
#                                       push and open pull requests with
{ lib, config, ... }:
let
  inherit (lib) mkOption types;
  top = config;
  cfg = config.github.agentsApp;
  secret = import ../_lib/secret.nix;
  zone = config.hetzner.host.agents.zone;
  redirect = "https://chat.${zone}/_github/app";
  manifest = {
    inherit (cfg) name;
    url = "https://status.mirazo.org/";
    description = "Kagamizo's agents: they write agents/* branches and open pull requests, which merge only as their change classes allow.";
    public = false;
    redirect_url = redirect;
    setup_url = redirect;
    setup_on_update = false;
    default_permissions = cfg.permissions;
    default_events = [ ];
  };
in
{
  options.github.agentsApp = {
    name = mkOption {
      type = types.strMatching "[A-Za-z0-9][A-Za-z0-9-]*";
      default = "kagamizo-agents";
    };
    permissions = mkOption {
      type = types.attrsOf (
        types.enum [
          "read"
          "write"
        ]
      );
      default = {
        contents = "write";
        pull_requests = "write";
        metadata = "read";
      };
      description = "The least the loop needs: push agents/* branches, open and merge pull requests.";
    };
    item = mkOption {
      type = types.strMatching "[a-z][a-z0-9-]*";
      default = "github-agents-app";
      description = "The host's state-vault note holding the App's id and private key (automation writes notes: modules/operations).";
    };
  };

  config = {
    # The key, where the host writes and reads it; its issuer is the
    # redirect the owner's click sends.
    secrets.profiles.host.GITHUB_AGENTS_APP_KEY =
      secret {
        kind = "encryption-key";
        issuer = "automation:github-app-redirect";
        needs = [ "approve-sign-in" ];
        description = "The agents' GitHub App: its id and private key (JSON: id, pem), from GitHub's manifest flow";
        inherit (cfg) item;
      }
      // {
        providers = [ "host-state" ];
        required = false;
      };

    perSystem =
      { pkgs, config, ... }:
      {
        packages.github-app-manifest = pkgs.writeText "github-app-manifest.html" ''
          <!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
          <title>Create the agents' GitHub App</title>
          <style>body{font:16px/1.5 system-ui,sans-serif;max-width:560px;margin:0 auto;padding:32px 16px;background:#fbfaf8;color:#1d1c1a}
          button{font:inherit;padding:12px 18px;border-radius:10px;border:1px solid #e4e1db;background:#fff;color:#2b5fa8;cursor:pointer}
          @media(prefers-color-scheme:dark){body{background:#151514;color:#ecebe8}button{background:#1e1e1c;border-color:#34322f;color:#8db4ee}}</style></head>
          <body><h1>The agents' GitHub App</h1>
          <p>One click: GitHub shows the App as declared (<code>${cfg.name}</code>, ${
            lib.concatStringsSep ", " (lib.mapAttrsToList (p: v: "${p}: ${v}") cfg.permissions)
          }); press <b>Create GitHub App</b> there. GitHub then hands the key to jingzo-host, which keeps it. Nothing to copy.</p>
          <form method="post" action="https://github.com/organizations/${top.github.org}/settings/apps/new?state=${cfg.name}">
          <input type="hidden" name="manifest" value='${
            lib.replaceStrings [ "'" ] [ "&#39;" ] (builtins.toJSON manifest)
          }'>
          <button type="submit">Open GitHub to create ${cfg.name}</button></form>
          <p>Then install it on <code>kagamizo</code> when GitHub offers; that lands on the same host page.</p>
          </body></html>
        '';

        packages.github-app-token = pkgs.writeShellApplication {
          name = "github-app-token";
          runtimeInputs = [
            config.packages.secretspec
            pkgs.openssl
            pkgs.curl
            pkgs.jq
            pkgs.coreutils
          ];
          text = ''
            out=''${1:?usage: github-app-token OUT_FILE [profile]}
            profile=''${2:-host}
            export PROTON_PASS_KEY_PROVIDER=''${PROTON_PASS_KEY_PROVIDER:-fs}
            umask 077
            key=$(mktemp); trap 'rm -f "$key"' EXIT
            app=$(secretspec get GITHUB_AGENTS_APP_KEY --file ${config.packages.secretspec-toml} --profile "$profile" \
              --reason "github-app-token: sign a JWT for the agents' App")
            [ -n "$app" ] || { echo "github-app-token: no App key yet (the owner's click: github-app-manifest)" >&2; exit 1; }
            jq -j .pem <<<"$app" >"$key"
            appid=$(jq -r .id <<<"$app")
            unset app
            b64() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }
            now=$(date +%s)
            header=$(printf '{"alg":"RS256","typ":"JWT"}' | b64)
            claims=$(jq -nc --argjson n "$now" --arg i "$appid" '{iat: ($n - 60), exp: ($n + 540), iss: $i}' | b64)
            sig=$(printf '%s.%s' "$header" "$claims" | openssl dgst -sha256 -sign "$key" -binary | b64)
            jwt="$header.$claims.$sig"
            inst=$(curl -fsS -H "Authorization: Bearer $jwt" -H 'Accept: application/vnd.github+json' \
              https://api.github.com/app/installations | jq -r '.[0].id')
            [ -n "$inst" ] && [ "$inst" != null ] || { echo "github-app-token: the App is not installed anywhere yet" >&2; exit 1; }
            curl -fsS -X POST -H "Authorization: Bearer $jwt" -H 'Accept: application/vnd.github+json' \
              "https://api.github.com/app/installations/$inst/access_tokens" | jq -j .token >"$out"
            echo "github-app-token: a one-hour token for installation $inst written to $out"
          '';
        };
      };
  };
}
