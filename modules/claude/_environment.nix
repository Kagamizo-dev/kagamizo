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
        hosts = [
          "api.hetzner.cloud"
          # The marketing site's price list, besides `GET /pricing`
          "www.hetzner.com"
        ];
      };
      # Pinning and fetching models (DeepSeek Flash-class, quantized): the
      # API, the model files and the CDNs they redirect to.
      hugging-face = {
        reason = "Model pinning and downloads from Hugging Face (model hosting)";
        hosts = [
          "huggingface.co"
          "*.huggingface.co"
          "*.hf.co"
        ];
      };
      # The migration off Apple (modules/migration, modules/apple): iCloud's
      # sign-in (pyicloud), its reads (icloudpd, rclone iclouddrive) and the
      # content and CloudKit hosts its downloads redirect to.
      icloud = {
        reason = "iCloud sign-in and reads for the migration (modules/apple)";
        hosts = [
          "idmsa.apple.com"
          "appleid.apple.com"
          "gsa.apple.com"
          "setup.icloud.com"
          "*.icloud.com"
          "*.icloud-content.com"
          "*.apple-cloudkit.com"
          # The trusted-device 2FA prompt: the websocket the pinned pyicloud
          # opens (its hsa2 bridge; `icloud login` dials it through the proxy,
          # modules/apple/_icloud.py)
          "websocket.push.apple.com"
          "websocket.sandbox.push.apple.com"
        ];
      };
      # The migration tools' own documentation, for mapping them and the
      # providers' export pages (modules/migration).
      migration-docs = {
        reason = "The migration tools' and providers' documentation (modules/migration)";
        hosts = [
          "rclone.org"
          "developers.google.com"
          "learn.microsoft.com"
          "support.apple.com"
          "privacy.apple.com"
        ];
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
          # sign-in posts to (refused on a submitted sign-in, 2026-10-22),
          # and the asset and loader hosts its scripts name
          "cdn.mercury.com"
          "acdn.mercury.com"
          "ldr.mercury.com"
          "backend.mercury.com"
          "fp.mercury.com"
          # Public's web app: its API and the identity check at sign-in
          "plat.public.com"
          "*.hellopublic.com"
          "network.dv.socure.io"
          "ingestion.dv.socure.io"
          "ingestion.dv.socure.us"
          # Cloudflare's dashboard sign-in captcha (Turnstile)
          "challenges.cloudflare.com"
          # OpenRouter's sign-in (Clerk, and its bot protection)
          "clerk.openrouter.ai"
          "cdn.protect.clerk.com"
          # OpenRouter's credit top-up (Stripe's checkout)
          "js.stripe.com"
          "api.stripe.com"
          "m.stripe.network"
          "hooks.stripe.com"
          "checkout.stripe.com"
          # Northwest's client portal and the frontend it loads
          "accounts.northwestregisteredagent.com"
          "ct-frontend.corporatetools.com"
          # GitHub's web assets (organization creation is web-only), its
          # signup captcha and avatars
          "github.githubassets.com"
          "api.github.com"
          "octocaptcha.com"
          "avatars.githubusercontent.com"
          # Experian: the credit file's login, its email and freezes, and the
          # captcha its sign-in shows
          "usa.experian.com"
          "hcaptcha.com"
          "*.hcaptcha.com"
          # Hetzner's Cloud Console (its sign-in is behind a proof-of-work page)
          "console.hetzner.cloud"
          "console.hetzner.com"
          # Gitea: the hosted account Jingzo's vault holds a login for
          "gitea.com"
          # Substack: research publishing, and its assets
          "substack.com"
          "substackcdn.com"
          # arXiv's web assets
          "static.arxiv.org"
        ];
      };
      # Moving a login off qsearchllc_wy@outlook.com confirms at that
      # address, so the flows read its mailbox until it is retired last.
      outlook = {
        reason = "The outlook mailbox the old logins confirm at (modules/browser)";
        hosts = [
          "login.live.com"
          "account.live.com"
          "outlook.live.com"
          "login.microsoftonline.com"
          "outlook.office365.com"
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
      # Found needed on 2026-11-08 (the owner allows them for the next
      # session): the bank's links and audit, the trading research, the
      # build cache every command tried.
      cache = {
        reason = "The flake's own binary cache (nixConfig extra-substituters): refused all session";
        hosts = [ "cache.kagamizo.com" ];
      };
      banks = {
        reason = "Chase, Capital One and Credit One sign-in pages and their terms (bank links, the transaction audit)";
        hosts = [
          "chase.com"
          "www.chase.com"
          "secure.chase.com"
          "capitalone.com"
          "www.capitalone.com"
          "verified.capitalone.com"
          "myaccounts.capitalone.com"
          "creditonebank.com"
          "www.creditonebank.com"
          # Discover and PayPal: the other two institutions bank.aggregators
          # tracks, for their terms and statements
          "discover.com"
          "www.discover.com"
          "portal.discover.com"
          "paypal.com"
          "www.paypal.com"
        ];
      };
      bank-links = {
        reason = "Bank-link providers' own institution lists and APIs, to verify coverage before one is chosen (bank.aggregators)";
        hosts = [
          "plaid.com"
          "dashboard.plaid.com"
          "production.plaid.com"
          "sandbox.plaid.com"
          "bridge.simplefin.org"
          "beta-bridge.simplefin.org"
          "teller.io"
          "api.teller.io"
          "stripe.com"
          "docs.stripe.com"
          "api.stripe.com"
          # Jingzo's Stripe account and the Financial Connections purpose
          # review (its Terms s2.1(a)); Link's consumer terms, which those
          # Terms require each consent to meet
          "dashboard.stripe.com"
          "link.com"
        ];
      };
      wallet-passes = {
        reason = "Cards as Google Wallet passes (bank/wallet-passes): the Wallet API, its issuer console and its docs, mapped before use";
        hosts = [
          "walletobjects.googleapis.com"
          "oauth2.googleapis.com"
          "pay.google.com"
          "developers.google.com"
        ];
      };
      public-help = {
        reason = "Public's help centre: the crypto daily pause and account security (bank.venues)";
        hosts = [ "help.public.com" ];
      };
      research-data = {
        reason = "Market and weather data the research and weather strategies read (research.dataVendors, weather-rules)";
        hosts = [
          "api.open-meteo.com"
          "api.weather.gov"
          "query1.finance.yahoo.com"
          "query2.finance.yahoo.com"
          "fc.yahoo.com"
          "api.stlouisfed.org"
          "fred.stlouisfed.org"
        ];
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
