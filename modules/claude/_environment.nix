# The cloud environment's network allowlist, declared here and pasted into the
# environment settings (Network access: Custom). It cannot apply itself: the
# sandbox's limits are set outside the sandbox, on purpose.
#
#   nix build .#claude-allowed-domains && cat result
#
# Each host is type-checked, so a typo fails `nix flake check` instead of
# silently allowing or blocking the wrong thing.
{ lib, ... }:
let
  inherit (lib) mkOption types;

  # A hostname, optionally with a leading "*." (matches every subdomain).
  domain = types.strMatching "(\\*\\.)?([a-z0-9]([a-z0-9-]*[a-z0-9])?\\.)+[a-z]{2,}";

  group = types.submodule {
    options = {
      enable = mkOption {
        type = types.bool;
        default = true;
      };
      reason = mkOption { type = types.str; };
      hosts = mkOption { type = types.nonEmptyListOf domain; };
    };
  };
in
{
  options.network = {
    includeDefaults = mkOption {
      type = types.bool;
      description = ''Tick "Also include default list of common package managers".'';
    };
    allow = mkOption { type = types.attrsOf group; };
  };

  config.network = {
    # The defaults already cover GitHub release downloads, *.r2.cloudflarestorage.com
    # (OpenTofu state) and *.nixos.org.
    includeDefaults = true;

    allow = {
      cloudflare = {
        reason = "Cloudflare API: OpenTofu layers and the registrar (modules/cloudflare)";
        hosts = [
          "api.cloudflare.com"
          # OAuth device login (cloudflare-login): the root session
          "dash.cloudflare.com"
        ];
      };
      proton = {
        reason = "pass-cli and secretspec reading Proton Pass";
        hosts = [
          "proton.me"
          "*.proton.me"
        ];
      };
      openrouter = {
        reason = "Models and key management (modules/openrouter)";
        hosts = [ "openrouter.ai" ];
      };
      mercury = {
        reason = "Virtual cards (modules/mercury); card details go to the vault API";
        hosts = [
          "api.mercury.com"
          "vault-api.mercury.com"
          # `mercury-session login`: the CLI's OAuth sign-in and refresh
          "oauth2.mercury.com"
        ];
      };
      northwest = {
        reason = "Registered agent and filings through Northwest's MCP server (modules/northwest)";
        hosts = [
          "mcp.northwestregisteredagent.com"
          # OAuth sign-in and refresh (its identity server)
          "id.northwestregisteredagent.com"
          # The tools and connection pages the catalog cites
          "www.northwestregisteredagent.com"
        ];
      };
      public = {
        reason = "Brokerage reads and orders (modules/public), the first trading backend";
        hosts = [ "api.public.com" ];
      };
      hetzner = {
        reason = "The always-on host: hcloud and OpenTofu (modules/hetzner)";
        hosts = [ "api.hetzner.cloud" ];
      };
      interactive-brokers = {
        reason = "The second trading backend: IB Gateway's sign-in and IBKR's Web API (modules/trading)";
        hosts = [
          "api.ibkr.com"
          "*.interactivebrokers.com"
          # IB Gateway's container image
          "ghcr.io"
          "*.ghcr.io"
        ];
      };
      opencode = {
        reason = "OpenCode's config schema and model list, for the swarms (modules/governance)";
        hosts = [
          "opencode.ai"
          "models.dev"
        ];
      };
      arxiv = {
        reason = "Jingzo's and Mirazo's research: the query API (modules/arxiv, paused)";
        hosts = [
          "arxiv.org"
          "export.arxiv.org"
        ];
      };
      # Pages the declared signups, capabilities and findings cite, so a session
      # can re-read them (and browser automation can reach the signups).
      sources = {
        reason = "Provider pages cited by accounts.plans and signups";
        hosts = [
          "public.com"
          "mercury.com"
          "app.mercury.com"
          "docs.mercury.com"
          "accounts.hetzner.com"
          "docs.hetzner.cloud"
          "docs.hetzner.com"
          "info.arxiv.org"
          "blog.arxiv.org"
          # Wyoming's business search: Kagamizo's filing and standing
          "wyobiz.wyo.gov"
        ];
      };
      # What each provider's web app loads to sign in and work, found by
      # loading its sign-in page and keeping every refused host that is the
      # app itself (scripts, its API, its sign-in, its captcha); analytics
      # and trackers are left out. For the browser flows (modules/browser).
      # A page only loading is not enough: Mercury's API and device check
      # showed only once its sign-in was submitted.
      browser = {
        reason = "Provider web apps the browser flows drive (modules/browser)";
        hosts = [
          # Mercury's web app: its scripts, its API, the device check its
          # sign-in posts to (refused on a submitted sign-in, 2026-10-22)
          "cdn.mercury.com"
          "backend.mercury.com"
          "fp.mercury.com"
          # Public's web app: its API and the identity check at sign-in
          "plat.public.com"
          "prod-api.154310543964.hellopublic.com"
          "ingestion.dv.socure.io"
          # Cloudflare's dashboard sign-in captcha (Turnstile)
          "challenges.cloudflare.com"
          # OpenRouter's sign-in (Clerk)
          "clerk.openrouter.ai"
          # Northwest's client portal
          "accounts.northwestregisteredagent.com"
          # GitHub's web assets (organization creation is web-only)
          "github.githubassets.com"
          "api.github.com"
          # Experian: the credit file's login, its email and freezes
          "usa.experian.com"
          # Substack: research publishing
          "substack.com"
          # arXiv's web assets
          "static.arxiv.org"
        ];
      };
      # The legal corpus (modules/legal): primary sources, mirrored with
      # their versions so every citation points at a fixed text.
      legal = {
        reason = "US and international primary law, IRS guidance, case law (modules/legal)";
        hosts = [
          "www.ecfr.gov"
          "uscode.house.gov"
          "www.govinfo.gov"
          "api.govinfo.gov"
          "www.federalregister.gov"
          "api.congress.gov"
          "www.irs.gov"
          "www.courtlistener.com"
          "www.ustaxcourt.gov"
          "wyoleg.gov"
          "sos.wyo.gov"
          "www.sec.gov"
          "data.sec.gov"
          "eur-lex.europa.eu"
          "www.legislation.gov.uk"
        ];
      };
      # Checking that published records resolve, after an infra apply.
      dns = {
        reason = "DNS-over-HTTPS lookups to verify published records";
        hosts = [
          "cloudflare-dns.com"
          "dns.google"
        ];
      };
      nix-caches = {
        reason = "Binary caches the flake trusts (nixos-raspberrypi)";
        hosts = [ "*.cachix.org" ];
      };
      # Live data for running World Monitor / God's Eye View in a session.
      globe-data = {
        enable = false;
        reason = "Map tiles and public feeds for the globe apps";
        hosts = [
          "worldmonitor.app"
          "*.worldmonitor.app"
          "server.arcgisonline.com"
          "services.arcgisonline.com"
          "tile.openstreetmap.org"
          "opensky-network.org"
          "earthquake.usgs.gov"
          "api.cesium.com"
        ];
      };
    };
  };
}
