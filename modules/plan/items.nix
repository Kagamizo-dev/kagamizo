# The plan's items (./plan.nix), track by track, in order: an item's place
# in its list is its order. Gathered on 2026-11-07 from HANDOFF.md, the
# teams' backlog, the Cloudflare gaps, every paper's gaps and the plans of
# 2026-11-04 and 2026-11-07, then deduplicated. Change the plan here.
{ lib, ... }:
let
  track =
    t: entries:
    lib.listToAttrs (
      lib.imap1 (
        n: e:
        lib.nameValuePair "${t}/${e.id}" (
          {
            track = t;
            order = n;
          }
          // removeAttrs e [ "id" ]
        )
      ) entries
    );
  owner = d: {
    blocked = "owner-decision";
    decision = d;
  };
  action = {
    blocked = "owner-action";
  };
  credit = {
    blocked = "credit";
  };
  hardware = {
    blocked = "hardware";
  };
  upstream = {
    blocked = "upstream";
  };
in
{
  plan.items =
    track "plan" [
      {
        id = "planning-app";
        title = "The planning app: one typed plan, the source of truth";
        status = "active";
      }
      {
        id = "issues-from-plan";
        title = "GitHub issues and the board rendered from the plan";
        dependsOn = [ "plan/planning-app" ];
      }
      (
        {
          id = "project-board";
          title = "A board view of the plan, laid out like Linear";
          backlog = "design/project-board";
          dependsOn = [ "plan/issues-from-plan" ];
        }
        // credit
      )
      {
        id = "handoff-sessions";
        title = "HANDOFF.md keeps sessions only; the plan holds the work";
        dependsOn = [ "plan/planning-app" ];
      }
    ]
    // track "os" [
      {
        id = "vm-boot-tests";
        title = "Boot tests in CI for every NixOS image (the Yoga's USB image, the Pi's SD image)";
      }
      (
        {
          id = "yoga-boot";
          title = "Boot the Yoga from its USB image and run the shell on its screen";
        }
        // hardware
      )
      {
        id = "grapheneos-image";
        title = "GrapheneOS's stable factory image wrapped in Nix: pinned by hash, signature checked, flashing wrapped";
      }
      {
        id = "grapheneos-params";
        title = "The phone's settings, permissions and default apps declared, applied at first boot";
        dependsOn = [ "os/grapheneos-image" ];
      }
      (
        {
          id = "pixel-flash";
          title = "Flash our image onto the Pixel and relock the bootloader with our key";
          dependsOn = [ "os/grapheneos-params" ];
        }
        // owner "pixel-adb"
      )
      {
        id = "fdroid-store";
        title = "Our own F-Droid repository of vetted, accountless apps, built by Nix";
      }
      {
        id = "android-twin-test";
        title = "A CI boot test of the phone's twin with our parameters";
        dependsOn = [ "os/grapheneos-params" ];
      }
      (
        {
          id = "pi-serving-test";
          title = "Test the Pi serving the shell to the phone (.local, tether or hotspot)";
        }
        // hardware
      )
      (
        {
          id = "box64";
          title = "box64 or FEX on the Pi, once its kernel's page size is checked";
        }
        // hardware
      )
      {
        id = "sd-probe";
        title = "Flash an SD or USB image from the Yoga or the phone and probe a device of ours";
      }
      {
        id = "machines-contract";
        title = "A typed contract for every server, container and device";
      }
    ]
    // track "shell" [
      {
        id = "theme";
        title = "The theme: retro pixel art with depth, academic type, a gaming and media feel; fonts, palette, sprites and icons for the shell and every app";
      }
      {
        id = "templates";
        title = "Views from existing open-source templates and kits (pixel art, game UI, dashboards), never drawn from scratch; game-like ease: save states, nothing lost, always a way back";
        dependsOn = [ "shell/theme" ];
      }
      {
        id = "horizontal";
        title = "Horizontal tiling: apps as columns swiped left and right, a workspace per mode";
      }
      {
        id = "launchers";
        title = "Launchers: a card that opens its own library of titles, with artwork";
        dependsOn = [ "shell/horizontal" ];
      }
      (
        {
          id = "steam";
          title = "The Steam launcher on the Yoga, and a perf target for the web build";
          backlog = "upkeep/shell-steam-and-perf";
          dependsOn = [ "shell/launchers" ];
        }
        // owner "steam"
      )
      {
        id = "minecraft";
        title = "The Minecraft launcher (Prism), with our world as a title";
        dependsOn = [
          "shell/launchers"
          "world/pumpkin"
        ];
      }
      {
        id = "trading-launcher";
        title = "The trading launcher over Public, Mercury and NautilusTrader";
        dependsOn = [
          "shell/launchers"
          "trading/nautilus-rust"
        ];
      }
      (
        {
          id = "os-web";
          title = "Serve the shell at os.jingzo.org behind Access";
          status = "active";
          backlog = "upkeep/shell-web";
        }
        // owner "cloudflare-os"
      )
      {
        id = "app-views";
        title = "Every app draws its own view, live data included";
      }
      {
        id = "where-local";
        title = "Cards resolve to the Pi when it is reachable, to the host otherwise";
      }
      (
        {
          id = "settings-layout";
          title = "The status page laid out as settings";
          backlog = "design/settings-layout";
        }
        // credit
      )
      (
        {
          id = "account-dashboards";
          title = "A page per account, with its live numbers";
          backlog = "design/account-dashboards";
        }
        // credit
      )
      {
        id = "status-overflow";
        title = "Fix the status page's horizontal overflow at 390 px";
      }
      (
        {
          id = "home-subdomain";
          title = "The homepage at home.jingzo.org";
          dependsOn = [ "shell/os-web" ];
        }
        // owner "cloudflare-os"
      )
      (
        {
          id = "web-offline";
          title = "The installed web app working offline, without JavaScript of ours";
        }
        // upstream
      )
    ]
    // track "apps" [
      {
        id = "restructure";
        title = "Regroup the 64 modules: apps, providers inside apps, the OS, Settings and build tooling";
      }
      {
        id = "library-rule";
        title = "Lean: every module is an app with a team";
        dependsOn = [ "apps/restructure" ];
      }
      {
        id = "team-per-app";
        title = "A charter and a team for every app";
        dependsOn = [ "apps/restructure" ];
      }
      {
        id = "team-vaults";
        title = "A Proton Pass vault and token per team, not per entity";
        dependsOn = [ "apps/team-per-app" ];
      }
      {
        id = "team-addresses";
        title = "An address per team, a Pass alias; the mailbox wrapper shows a team only its mail";
        dependsOn = [ "apps/team-per-app" ];
      }
      (
        {
          id = "agent-mail";
          title = "Teams send mail as themselves";
          dependsOn = [ "apps/team-addresses" ];
        }
        // owner "agent-mail"
      )
      {
        id = "domains";
        title = "Every app its own page as well as its card, at its own domain (<app>.jingzo.org by default)";
        dependsOn = [ "apps/restructure" ];
      }
      {
        id = "cli-settings";
        title = "Every app's settings declared and set through its CLI";
        dependsOn = [ "apps/restructure" ];
      }
      {
        id = "orca-verify";
        title = "Verify Orca runs each team as its own user; mint the swarm tokens";
        dependsOn = [ "apps/team-vaults" ];
      }
      (
        {
          id = "models";
          title = "A model per task from Hugging Face: the cheapest that meets its measured score";
          backlog = "reverse-engineering/model-registry";
        }
        // credit
      )
      (
        {
          id = "trained-models";
          title = "Models trained for a team's own function";
          dependsOn = [ "apps/models" ];
        }
        // owner "gpu"
      )
    ]
    // track "identity" [
      {
        id = "account-dossiers";
        status = "active";
        title = "Every account a typed Proton Pass item holding every field its provider asks for (identity, address, tax ids, documents by reference), prepared by the agents through pass-cli; only the password or passkey, second factors and liveness left to the owner";
      }
      {
        id = "signup-flows";
        title = "Sign-ups driven by the agents from the account's Pass item: by API or CLI where offered, a governed browser flow otherwise, stopping for the owner's authentication and approval of the submission";
        dependsOn = [
          "identity/account-dossiers"
          "agents/browser"
        ];
      }
      {
        id = "footprint";
        title = "The owner's whole digital identity mapped onto the apps: documents, the professional and academic record, accounts, domains, public profiles; every value in Proton";
      }
      (
        {
          id = "personal-docs";
          title = "The personal documents' Pass items made: passport, resume, degrees, W-2s";
        }
        // action
      )
      {
        id = "mail-agents";
        title = "Mail agents per domain: statements, W-2s, alerts and confirmations read from the mailboxes into the apps, each team only its alias";
        dependsOn = [ "apps/team-addresses" ];
      }
      {
        id = "sign-in-types";
        title = "Each account's sign-in and second factors typed";
      }
      {
        id = "sms-gate";
        title = "Lean refuses a provider whose only second factor is SMS; audit what we hold";
        dependsOn = [ "identity/sign-in-types" ];
      }
      {
        id = "totp-in-pass";
        title = "Proton Pass's authenticator codes the default second factor";
        dependsOn = [ "identity/sign-in-types" ];
      }
      {
        id = "account-links";
        title = "Every request to the owner as a Proton Pass link in #owner";
        backlog = "upkeep/account-links";
        dependsOn = [ "agents/matrix-bots" ];
      }
      (
        {
          id = "logins-on-domains";
          title = "Every login on its owner's domain (Northwest, Public, Cloudflare, Experian, IBKR, GitHub)";
        }
        // action
      )
      (
        {
          id = "public-login";
          title = "Public's sign-in moved onto its declared address before its exception ends on 2026-11-30";
          decision = "public-login";
        }
        // action
      )
      {
        id = "undeclared-logins";
        title = "Declare the remaining Pass logins (Jingzo, Kagamizo)";
      }
      (
        {
          id = "old-swarms";
          title = "Delete the six old swarm agents before 2026-11-21";
        }
        // action
      )
      (
        {
          id = "github-orgs";
          title = "Three GitHub organisations, the Claude app on each";
        }
        // action
      )
      (
        {
          id = "github-app-key";
          title = "Confirm the GitHub App page was opened and its key reached the host";
        }
        // action
      )
      {
        id = "github-state";
        title = "Apply github-state for the new issues";
      }
      {
        id = "github-board";
        title = "GitHub Projects and the organisation's settings from the bootstrap runner";
      }
      (
        {
          id = "credit-bureaus";
          title = "Experian's email, alerts and freezes at the three bureaus";
        }
        // action
      )
      (
        {
          id = "northwest-cli";
          title = "Northwest's CLI sign-in (an OAuth client that supports loopback)";
        }
        // upstream
      )
      {
        id = "host-principal";
        title = "The host as a Cedar principal; audit records agents can read";
      }
      {
        id = "frozen-wrappers";
        title = "Every wrapper frozen, with a Cedar deny for calls outside its closure";
      }
      {
        id = "lean-calls";
        title = "Lean types for every CLI call, Rust types from them, the Cedar base layer in Lean";
      }
      {
        id = "mercury-cli";
        title = "One Rust program for mercury and cards; its login as a flow";
      }
      {
        id = "automation-blob";
        title = "Automation-written values in one typed Pass item";
      }
      (
        {
          id = "registrar";
          title = "Registrar prerequisites: payment, contact, agreement";
        }
        // action
      )
    ]
    // track "infra" [
      {
        id = "host-ci";
        title = "Confirm checks.jingzo-host is green in CI";
      }
      {
        id = "live-tiles";
        title = "Live tiles: tunnel, host, spend and balances, from a read-only Worker";
      }
      {
        id = "ci-rust";
        title = "CI declared in Rust: the hand-written workflows, host settings in OpenTofu";
      }
      (
        {
          id = "build-box";
          title = "A self-hosted build machine, once CI's times are measured";
        }
        // owner "build-box"
      )
      (
        {
          id = "trusted-header";
          title = "Trusted-header sign-in for OpenCode and dsh";
        }
        // upstream
      )
      {
        id = "pi-access";
        title = "Tunnel and Access for the Pi's services; Workers and Pages in the zones";
      }
      {
        id = "stale-state";
        title = "Delete the old tofu-state notes after the next apply";
      }
    ]
    // track "agents" [
      {
        id = "browser";
        title = "Agents' own browsers: a headless engine per team (Lightpanda for speed, Chromium for full pages), Rust over CDP, every flow typed and governed by Cedar";
        backlog = "browser/engine-and-aliases";
      }
      {
        id = "host-runner";
        title = "The agents' runner on the host";
        status = "done";
        backlog = "upkeep/host-runner";
      }
      (
        {
          id = "credit";
          title = "OpenRouter credit for the teams, pinned to the cheap providers";
        }
        // owner "openrouter-credit"
      )
      (
        {
          id = "topup-flow";
          title = "The OpenRouter top-up as a flow within the card's limit";
          backlog = "upkeep/openrouter-topup-flow";
          dependsOn = [ "agents/browser" ];
        }
        // credit
      )
      (
        {
          id = "runner-on";
          title = "Turn the runner on";
          dependsOn = [ "agents/credit" ];
        }
        // owner "runner"
      )
      (
        {
          id = "matrix-bots";
          title = "Matrix bots: a room per team and #owner";
          backlog = "upkeep/matrix-bots";
        }
        // credit
      )
      {
        id = "github-matrix";
        title = "GitHub's events in the teams' rooms";
        dependsOn = [ "agents/matrix-bots" ];
      }
      {
        id = "run-backlog";
        title = "Run the backlog in the plan's order once credit returns";
        dependsOn = [ "agents/credit" ];
      }
      {
        id = "dsh-sandbox";
        title = "dsh's shell under a dynamic user, reaching only declared hosts";
      }
      {
        id = "spend-tiles";
        title = "Spend per team on the homepage";
      }
    ]
    // track "trading" [
      {
        id = "public-rust";
        title = "Public's client in Rust";
        status = "done";
        backlog = "upkeep/trading-public-rust";
      }
      {
        id = "trade-rust";
        title = "trade in Rust";
        status = "done";
        backlog = "upkeep/trading-trade-rust";
      }
      {
        id = "nautilus-map";
        title = "NautilusTrader's Rust crates mapped";
        status = "done";
        backlog = "reverse-engineering/nautilus-rust";
      }
      {
        id = "paper";
        title = "The trading paper";
        status = "done";
        backlog = "research-jingzo/trading-paper";
      }
      {
        id = "paper-visible";
        title = "The paper days on the host's console every hour (live after the 04:40 switch)";
        status = "active";
      }
      {
        id = "rehearsal";
        title = "Every paper day rehearses the live path up to placing; an order still working is cancelled; only a fill opens a position";
        status = "done";
      }
      {
        id = "readiness";
        title = "Every step of the live lifecycle typed with what exercises it; Lean keeps every strategy short of live until each has met the real backend";
        status = "done";
      }
      {
        id = "dry-run";
        title = "The agents' strategy dry-run daily at no cost: TradingAgents on the host's small quantized model, then its paper day and rehearsal";
        status = "done";
      }
      {
        id = "nautilus-adapter";
        title = "Public as a NautilusTrader adapter (data and execution clients); paper on Nautilus's sandbox, live on ours, the same node: a crypto round trip proved both ways";
        status = "done";
      }
      {
        id = "reconcile";
        title = "Reconcile the day's positions against Public's portfolio";
        # 2026-11-08: positions reconcile through Nautilus on restart (with
        # their cost basis); open orders and fills are not reported yet.
        status = "active";
      }
      {
        id = "nautilus-strategies";
        title = "Every strategy a Nautilus strategy with its close: event-rule maker-only to settlement, agent-option sell to close, baselines beside them; the hand-rolled ledger and read-back deleted";
        dependsOn = [ "trading/nautilus-adapter" ];
      }
      {
        id = "measured-costs";
        title = "Latency, spread and fees measured from Public into the sandbox's models; implementation shortfall on every order";
        dependsOn = [ "trading/nautilus-strategies" ];
      }
      {
        id = "validity-gates";
        title = "Live gated on forward paper days after the model's cutoff, deflated Sharpe, PBO over logged variants and beating the baseline (Lean)";
        dependsOn = [ "trading/measured-costs" ];
      }
      {
        id = "approval-link";
        title = "Each live order approved by the owner through a Proton Pass link in #owner";
        dependsOn = [ "identity/account-links" ];
      }
      (
        {
          id = "canary";
          title = "One canary order: placed far from the market, read back, cancelled; place, read-back and cancel meet the real backend";
          dependsOn = [ "trading/paper-days" ];
        }
        // owner "canary"
      )
      {
        id = "paper-days";
        title = "Check the host's first paper days and the ledger";
        dependsOn = [ "trading/paper-visible" ];
      }
      {
        id = "paper-evidence";
        title = "The paper ledger copied into the repository as the promotion's evidence";
        dependsOn = [ "trading/paper-days" ];
      }
      {
        id = "nautilus-rust";
        title = "Backtest and paper on NautilusTrader's Rust crates; the trading Python deleted";
        backlog = "upkeep/trading-nautilus-rust";
        dependsOn = [ "trading/nautilus-map" ];
      }
      {
        id = "weather-backtest";
        title = "The weather backtest on live sources, and its first real result";
        status = "active";
        backlog = "research-jingzo/weather-backtest";
      }
      {
        id = "grounded-sources";
        title = "Every signal and settlement from a declared source";
        backlog = "research-jingzo/grounded-sources";
      }
      {
        id = "options-settle";
        title = "Options settlement in paper-settle";
      }
      (
        {
          id = "agent-paper";
          title = "Agent-driven paper days and research runs on the host";
          dependsOn = [ "agents/runner-on" ];
        }
        // credit
      )
      {
        id = "event-backtest";
        title = "A backtest over settled event contracts, then the commodity options leg";
      }
      (
        {
          id = "live-gate";
          title = "Five paper days, P&L at least 0, drawdown at most 20%, then the owner's dated promotion";
          dependsOn = [ "trading/paper-days" ];
        }
        // owner "trading-limits"
      )
      (
        {
          id = "seed";
          title = "Deposit the seed into Public once paper is validated";
          dependsOn = [ "trading/live-gate" ];
        }
        // action
      )
      {
        id = "options-level-read";
        title = "Read the options level from Public's API on the host (recorded: 1, on 2026-11-04; weather-rules needs none, spy-agents needs 2)";
      }
      (
        {
          id = "options-level";
          title = "Raise Public's options level for the multi-leg strategies";
          dependsOn = [ "trading/options-level-read" ];
        }
        // action
      )
      (
        {
          id = "event-contracts";
          title = "Confirm event contracts are on for Public's account";
        }
        // action
      )
      {
        id = "entity";
        title = "The personal account trades for now (public-mirazo)";
        status = "done";
        decision = "trading-entity";
      }
      {
        id = "ibkr";
        title = "IBKR as a second backend";
      }
      {
        id = "lean-counters";
        title = "The backtest's counters decided from an external source";
      }
    ]
    // track "research" [
      (
        {
          id = "publishing";
          title = "Where research is published";
        }
        // owner "publishing"
      )
      {
        id = "publishing-targets";
        title = "The publishing targets as declared accounts";
        dependsOn = [ "research/publishing" ];
      }
      {
        id = "verso";
        title = "Papers rendered with Verso; strategy papers off Typst";
      }
    ]
    // track "bank" [
      {
        id = "app";
        title = "The bank app: one module wrapping Mercury, Public and IBKR, paper and live trading, legal and tax, its lawyers and accountants as its teams";
        status = "done";
      }
      {
        id = "ledger";
        title = "One double-entry ledger of every flow in and out: accounts, cards, trades, entities, loans";
        dependsOn = [ "bank/app" ];
      }
      {
        id = "flows";
        title = "Loans and contributions between entities and to services, each a typed flow the owner approves";
        dependsOn = [ "bank/ledger" ];
      }
      {
        id = "terms";
        title = "Each provider's terms typed and checked: automated trading, data use, an LLC's account (Public first)";
        status = "done";
        dependsOn = [ "bank/app" ];
      }
      {
        id = "irs";
        title = "IRS obligations typed: EINs, returns, estimated tax dates, the 475(f) election, each with its deadline";
        dependsOn = [ "bank/app" ];
      }
      {
        id = "state";
        title = "State obligations typed: the Wyoming annual report and its tax, the registered agent's renewals";
        dependsOn = [ "bank/app" ];
      }
      {
        id = "registered-agent";
        title = "Northwest as the bank's registered agent: its documents and mail read into the app";
        dependsOn = [ "identity/northwest-cli" ];
      }
      {
        id = "documents";
        title = "Every legal and tax record in the app: formation, EIN letters, statements, filings, kept in Proton Drive";
        dependsOn = [ "bank/app" ];
      }
      {
        id = "foreign";
        title = "Foreign accounts and currencies (Brazil's real first): typed, with their reporting (FBAR, FATCA)";
        dependsOn = [ "bank/ledger" ];
      }
      {
        id = "status";
        title = "Each obligation's status (filed, paid, not owed, extended) with its evidence; past due flagged";
        status = "done";
      }
      {
        id = "authorities";
        title = "Every authority typed with its interfaces (IRS, Treasury, FinCEN, SEC, FINRA, CFTC, Wyoming, the rules' text)";
        status = "done";
      }
      {
        id = "estimated-tax";
        title = "2026's estimated tax: not owed, the W-2 withholding covers it";
        status = "done";
      }
      {
        id = "residence";
        title = "Texas declared as the state of residence";
        status = "done";
        decision = "residence-state";
      }
      (
        {
          id = "mark-to-market";
          title = "Elect section 475(f) for 2027 or not, by 2027-04-15 (it cannot be made late)";
        }
        // owner "mtm-election"
      )
      {
        id = "mercury-events";
        title = "Mercury's webhook events, signature checked, as the ledger's feed";
        dependsOn = [ "bank/app" ];
      }
      {
        id = "mercury-token";
        title = "Mercury's token types typed, and a keep-alive inside its 45 days";
      }
      {
        id = "mercury-gaps";
        title = "Mercury's uncatalogued endpoints: credit statements, account cards, transfer approvals, auto-transfer rules, merchants, receipts, budgets";
      }
      {
        id = "public-orders";
        title = "Public's newer order fields: brackets, trailing stops, on-close, 24-hour sessions, tax-lot matching";
      }
      {
        id = "northwest-catalog";
        title = "Northwest's live tool list read from its server; the signature tools";
        dependsOn = [ "identity/northwest-cli" ];
      }
      (
        {
          id = "tax-forms";
          title = "The year's 1099s fetched by hand: no provider offers them by API";
        }
        // action
      )
      {
        id = "statements-by-mail";
        title = "Chase, the cards and PayPal wired by their mailed statements and alerts";
        dependsOn = [ "identity/mail-agents" ];
      }
      {
        id = "credit-file";
        title = "The credit file read from Experian: every line, its limit and status, every inquiry";
      }
      {
        id = "w2-intake";
        title = "W-2s read from email into the return's inputs and into Proton";
        dependsOn = [ "identity/mail-agents" ];
      }
      (
        {
          id = "wyoming-report";
          title = "Wyoming's annual report kept up (owed even with no revenue): Jingzo's formation month recorded";
          dependsOn = [ "bank/jingzo-record" ];
        }
        // action
      )
      {
        id = "venues";
        title = "Every venue typed with its classes, weekly sessions in UTC and tax treatment; the hours of the week covered, proved";
        status = "done";
      }
      (
        {
          id = "ibkr-gateway";
          title = "IBKR's Gateway on the host: futures across time zones and forex through the LLC's account, on NautilusTrader's adapter";
          dependsOn = [ "trading/nautilus-rust" ];
        }
        // owner "ibkr-gateway"
      )
      {
        id = "public-overnight";
        title = "Public's 24-hour weekday session in our order types";
        dependsOn = [ "bank/public-orders" ];
      }
      {
        id = "public-crypto";
        title = "Crypto on Public in our client and its paper days: with Kalshi, all 168 hours of the week on the one account (the daily pause confirmed first)";
        # 2026-11-08: crypto orders (an amount, not a quantity) in the client,
        # the stub and the engine; btc-agents dry-runs daily on the host with
        # its fee-marked ledger. Left: the pause, and the paper days.
        status = "active";
      }
      {
        id = "daylight";
        title = "Venue sessions in their exchanges' own time zones, turned into UTC by each daylight-saving rule, checked over seven reference weeks";
        status = "done";
      }
      {
        id = "around-the-clock";
        title = "Require every hour of the week covered: Public's crypto with Kalshi gives 168 of 168";
        dependsOn = [ "bank/public-crypto" ];
      }
      {
        id = "account-hub";
        title = "Public kept as the trading account (the owner's choice, 2026-11-08); IBKR held as the LLC's, unused for now";
        status = "done";
        decision = "account-hub";
      }
      {
        id = "holidays";
        title = "Federal holidays in due dates (MLK Day falls on January 15 in 2029)";
      }
      {
        id = "presentation";
        title = "A small design group for the bank deciding how its data is shown on the desktop and in the browser, from the shell's templates";
        dependsOn = [ "shell/templates" ];
      }
      {
        id = "page";
        title = "The bank's page and view: balances, obligations due, what waits on the owner";
        dependsOn = [
          "bank/ledger"
          "bank/irs"
        ];
      }
      (
        {
          id = "floor";
          title = "Set the Mercury floor";
        }
        // action
      )
      (
        {
          id = "wiring";
          title = "The money wiring between Mercury and Public";
        }
        // owner "wiring"
      )
      (
        {
          id = "owed";
          title = "Costs one entity pays for another";
        }
        // owner "owed-costs"
      )
      (
        {
          id = "kagamizo";
          title = "What Kagamizo becomes";
        }
        // owner "kagamizo-purpose"
      )
      (
        {
          id = "jingzo-record";
          title = "Jingzo's state, formation date and EIN; legal-sync and cards discover";
        }
        // action
      )
      (
        {
          id = "cards";
          title = "Mint the remaining declared Mercury cards after the tally";
          dependsOn = [ "migration/easy-switch" ];
        }
        // action
      )
      {
        id = "tax-history";
        title = "Public's history in the tax report";
      }
      {
        id = "legal-calendar";
        title = "The legal calendar in Catala: the 475(f) election, the Wyoming report, estimated tax";
      }
      {
        id = "legal-record";
        title = "Deterministic legal-record renders";
        backlog = "upkeep/deterministic-legal-record";
      }
      (
        {
          id = "records";
          title = "Where formation documents and statements are kept";
        }
        // owner "records"
      )
    ]
    // track "data" [
      {
        id = "logistics-team";
        title = "Charter a logistics team: suppliers, carriers, lockers, customs";
      }
      {
        id = "mercado-livre";
        title = "Mercado Livre's API: catalog, prices and stock in Brazil";
      }
      {
        id = "marketplaces";
        title = "eBay, AliExpress and Alibaba's open platform as typed sources";
      }
      {
        id = "shipping";
        title = "A multi-carrier shipping API: rates, transit times, tracking";
      }
      {
        id = "correios";
        title = "Correios for Brazil";
      }
      {
        id = "lockers";
        title = "Lockers and pickup points from each carrier";
      }
      {
        id = "trip-query";
        title = "Where a package can meet a trip: stock, transit and lockers joined";
        dependsOn = [
          "data/mercado-livre"
          "data/shipping"
          "data/lockers"
        ];
      }
      {
        id = "translation";
        title = "Local translation (NLLB): Portuguese, Spanish, Mandarin, English";
      }
      {
        id = "open-data";
        title = "Open data as typed sources: OpenStreetMap, Open-Meteo, Open Food Facts, libraries";
      }
      (
        {
          id = "developer-keys";
          title = "eBay's and Best Buy's developer keys";
        }
        // action
      )
    ]
    // track "make" [
      (
        {
          id = "inventory";
          title = "The inventory as typed items";
        }
        // owner "inventory"
      )
      {
        id = "cad";
        title = "CAD as code (build123d, FreeCAD), exported to twins and item models";
      }
      {
        id = "bom";
        title = "Every twin's bill of materials, process and tolerances";
        dependsOn = [ "make/cad" ];
      }
      {
        id = "quotes";
        title = "Quotes from suppliers' APIs and translated requests, typed on materials, machine time and labour";
        dependsOn = [
          "make/bom"
          "data/translation"
          "data/logistics-team"
        ];
      }
      {
        id = "storefront";
        title = "Our own open-source storefront: a specification typed in the browser becomes quotes";
        dependsOn = [ "make/quotes" ];
      }
      {
        id = "outfit-spec";
        title = "The outfit as a twin: the kit's slots as pockets, the fabric's requirements, its care";
        dependsOn = [ "make/bom" ];
      }
      {
        id = "outfit-quotes";
        title = "Quotes for the two outfits";
        dependsOn = [
          "make/outfit-spec"
          "make/quotes"
        ];
      }
    ]
    // track "kit" [
      {
        id = "typed";
        title = "The kit typed and proved";
        status = "done";
      }
      (
        {
          id = "purchases";
          title = "Price the proposals; the power bank first";
        }
        // owner "kit-purchases"
      )
      {
        id = "problems";
        title = "Name the failing fact in the kit's proof";
      }
      {
        id = "thermal-radio-ports";
        title = "Thermal limits, radio regulations and the ports between items";
      }
      (
        {
          id = "measure";
          title = "Measure mass and draw on the owner's own devices";
        }
        // hardware
      )
      (
        {
          id = "glasses-session";
          title = "A session on the Pi's own screen";
          dependsOn = [ "kit/purchases" ];
        }
        // hardware
      )
      {
        id = "endurance-perf";
        title = "A perf target for field endurance";
      }
    ]
    // track "world" [
      (
        {
          id = "pumpkin";
          title = "The Pumpkin server on the host";
          backlog = "twin/pumpkin-server";
        }
        // credit
      )
      {
        id = "map-tiles";
        title = "Map tiles and a Bevy viewer";
        backlog = "twin/map-tiles";
        dependsOn = [ "world/pumpkin" ];
      }
      {
        id = "districts";
        title = "Districts and rooms from the declarations";
        backlog = "builders/districts-and-rooms";
      }
      (
        {
          id = "azalea";
          title = "A bot per team in the world";
          backlog = "twin/azalea-bots";
          dependsOn = [ "world/pumpkin" ];
        }
        // upstream
      )
      {
        id = "reconcile";
        title = "Reconcile the Fabric mod and Mindcraft plans with Pumpkin and Azalea";
      }
      {
        id = "templates";
        title = "World templates as declarations";
      }
      {
        id = "npc";
        title = "The owner's character: a public schema, its values in Proton";
      }
      (
        {
          id = "spectrum";
          title = "A game client reaching the world through Cloudflare";
        }
        // owner "spectrum"
      )
    ]
    // track "media" [
      (
        {
          id = "discord";
          title = "The Discord relay live";
        }
        // action
      )
      {
        id = "drive-hop";
        title = "The Proton Drive hop on the host";
      }
      (
        {
          id = "multimodal";
          title = "Images and video: ComfyUI, Janus-Pro, Qwen-Image or FLUX, Wan 2.2";
        }
        // owner "gpu"
      )
    ]
    // track "security" [
      {
        id = "scope";
        title = "Our own surfaces typed; the probe effect; scanners carried";
        status = "done";
      }
      {
        id = "pipeline";
        title = "Security in every pipeline: code review, advisories, a secret scanner";
        backlog = "security/pipeline";
      }
      {
        id = "scheduled-scans";
        title = "Scheduled scans on the host, typed findings raised as issues";
        dependsOn = [ "security/pipeline" ];
      }
      {
        id = "datasets";
        title = "The scanners' datasets pinned";
      }
      {
        id = "tester-tokens";
        title = "The testers' Access service tokens";
        dependsOn = [ "shell/os-web" ];
      }
      {
        id = "vm-test";
        title = "A VM test: a scan of the host's loopback gives typed findings";
      }
      (
        {
          id = "radio";
          title = "Radio testing of our own devices";
          dependsOn = [ "kit/purchases" ];
        }
        // hardware
      )
    ]
    // track "reverse" [
      {
        id = "workbench";
        title = "The workbench and typed subjects";
        status = "done";
      }
      {
        id = "hardware-specs";
        title = "Our devices' hardware specifications as typed catalogs";
      }
      {
        id = "simulations";
        title = "Only the simulations a twin needs, never whole desktop apps";
        dependsOn = [ "make/cad" ];
      }
    ]
    // track "repo" [
      {
        id = "papers";
        title = "A paper for every module";
        backlog = "upkeep/module-papers";
        dependsOn = [ "apps/restructure" ];
      }
      {
        id = "languages";
        title = "Burn down the language exceptions";
        backlog = "upkeep/languages-burndown";
      }
      {
        id = "theorems";
        title = "Find theorems by elaborating Lean, not by pattern";
      }
      {
        id = "secretspec-upstream";
        title = "Send the secretspec patch upstream";
      }
      {
        id = "perf-cuts";
        title = "Perf cuts: migrate's build, the catalog's coverage";
      }
      (
        {
          id = "main-pr";
          title = "The pull request into main";
        }
        // action
      )
    ]
    // track "migration" [
      (
        {
          id = "easy-switch";
          title = "Easy Switch imports, then the subscription tally";
        }
        // action
      )
      (
        {
          id = "icloud";
          title = "iCloud exports into Proton Drive on the host";
          dependsOn = [ "media/drive-hop" ];
        }
        // action
      )
      (
        {
          id = "chase";
          title = "Chase's Pass item and the iCloud app password";
        }
        // action
      )
      {
        id = "credit-report";
        title = "Read the credit report for each card's fate";
      }
    ];
}
