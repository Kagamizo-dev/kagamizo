# The plan's goals, tracks and the owner's decisions (./plan.nix). The items
# are in ./items.nix.
{
  plan = {
    goals = {
      carried = {
        title = "A researcher's whole stack, carried";
        why = "Everything in the pockets and sleeves of two outfits rotated and washed, offline-first, the phone the screen and the Pi the machine (2026-11-07).";
      };
      base = {
        title = "One base image on every device";
        why = "Our own Nix-wrapped, Rust-based image on Linux, GrapheneOS and the browser, with the shell's horizontal tiling and launchers; tested on every target; no iOS (2026-11-07).";
      };
      teams = {
        title = "Every app a module, every module a team";
        why = "Modules are app launchers whose settings are set through their CLIs; each has a team acting as a scoped user (its vault, address, Cedar principal, room), and the owner is root admin who approves what spends or needs more (2026-11-07).";
      };
      accountless = {
        title = "Data first, accounts only as providers";
        why = "APIs, CLIs, open data and OSINT before anything else; Proton Pass holds identity and TOTP; no provider whose 2FA needs a phone number; human-verification walls are deprioritised, never bypassed (2026-11-07).";
      };
      bank = {
        title = "Our own bank";
        why = "Legal and tax identity bound to every source of revenue: one app wrapping Mercury, Public and IBKR, trading paper and live, the registered agent, the IRS and the states, every flow in and out (foreign accounts included) and every loan between entities and services, with its own lawyers and accountants as its teams (2026-11-07).";
      };
      income = {
        title = "Income that runs by itself";
        why = "Algorithmic trading and published research, paper before money (2026-10-31, 2026-11-04).";
      };
      make = {
        title = "From a specification to a delivered thing";
        why = "Marketplaces, shipping, lockers and suppliers as data; digital twins of what we need, quoted on materials and machine time; our own storefront; the two outfits (2026-11-07).";
      };
      world = {
        title = "The business as a world";
        why = "The twin: a world where modules are buildings and teams are characters, Steam and Minecraft as launchers (2026-11-04, 2026-11-06).";
      };
    };

    tracks = {
      plan = {
        title = "Plan";
        goal = "teams";
        team = "upkeep";
      };
      os = {
        title = "Base images and device tests";
        goal = "base";
        team = "upkeep";
      };
      shell = {
        title = "Shell and launchers";
        goal = "base";
        team = "design";
      };
      apps = {
        title = "Modules as apps, a team for each";
        goal = "teams";
        team = "upkeep";
      };
      identity = {
        title = "Identity, accounts and logins";
        goal = "accountless";
        team = "upkeep";
      };
      infra = {
        title = "Infrastructure";
        goal = "base";
        team = "upkeep";
      };
      agents = {
        title = "Agents, credit and chat";
        goal = "teams";
        team = "upkeep";
      };
      trading = {
        title = "Trading";
        goal = "bank";
        team = "research-jingzo";
      };
      research = {
        title = "Research and publishing";
        goal = "income";
        team = "research-jingzo";
      };
      bank = {
        title = "The bank: legal, tax, treasury and its flows";
        goal = "bank";
        team = "accounting-jingzo";
      };
      data = {
        title = "Marketplaces, shipping and translation";
        goal = "make";
        team = "upkeep";
      };
      make = {
        title = "Twins, quotes, storefront and outfits";
        goal = "make";
        team = "twin";
      };
      kit = {
        title = "The carried kit";
        goal = "carried";
        team = "twin";
      };
      world = {
        title = "The twin world";
        goal = "world";
        team = "twin";
      };
      media = {
        title = "Media and multimodal";
        goal = "carried";
        team = "upkeep";
      };
      security = {
        title = "Security";
        goal = "base";
        team = "security";
      };
      reverse = {
        title = "Reverse engineering";
        goal = "make";
        team = "reverse-engineering";
      };
      repo = {
        title = "Repository, papers and languages";
        goal = "base";
        team = "upkeep";
      };
      migration = {
        title = "Leaving providers";
        goal = "accountless";
        team = "upkeep";
      };
    };

    decisions = {
      # Decided.
      agents-sign-in = {
        question = "Do agents sign up or sign in to third-party accounts?";
        answer = "Revised 2026-11-08: every account is a typed vault item in Proton Pass, prepared by the agents through pass-cli with every field the provider asks for, mapped from the owner's Proton identity; the agents drive the sign-up (API, CLI, or a governed browser flow) and leave the owner only what is truly human: the password or passkey, second factors, a liveness check, and approving the final submission (its terms and attestations). They never hold the owner's sign-in. (Before: 2026-11-07, agents only sent links.)";
      };
      modules-are-apps = {
        question = "Are there base modules beside the apps?";
        answer = "No (2026-11-07): modules are app launchers; programs such as tmux are dependencies inside the module that uses them; accounts are providers inside apps.";
      };
      grapheneos = {
        question = "Build GrapheneOS ourselves, or wrap its own stable image?";
        answer = "Wrap GrapheneOS's own stable image in Nix (2026-11-07).";
      };
      verification-walls = {
        question = "What happens with a provider behind a human-verification wall?";
        answer = "Deprioritised in favour of APIs, CLIs and open data, never bypassed (2026-11-07).";
      };
      ios = {
        question = "Support iOS?";
        answer = "No (2026-11-07): it needs another account; Android, Linux and the browser only.";
      };
      theme = {
        question = "What is the look of the base image and every app?";
        answer = "Retro and a little academic, with a gaming and media feel: 2D pixel art drawn with depth, like a pixelated game seen in three dimensions; professional type for reading (2026-11-07). The design team owns it.";
      };
      first-device = {
        question = "Which device is the first deployment and test target?";
        answer = "A laptop or PC on NixOS stable, the Yoga first (2026-11-07).";
      };

      # Open.
      cloudflare-os = {
        question = "Apply the Cloudflare plan that serves os.jingzo.org and the testers' Access (re-planned first)?";
        recommended = "Yes, after reading the re-plan.";
      };
      steam = {
        question = "Enable the unfree gamedev.steam on the Yoga?";
        recommended = "Yes: Steam is a launcher of the shell.";
      };
      pixel-adb = {
        question = "Is attaching the real Pixel over USB for flashing and provisioning a declared human step?";
        recommended = "Yes: flashing our GrapheneOS image needs it once.";
      };
      kit-purchases = {
        question = "Which kit proposals to price, the endurance to prove, and the power bank first?";
        recommended = "Price the bank first; eight hours.";
      };
      openrouter-credit = {
        question = "Top up OpenRouter or raise the fleet key (spent at $25), and pin agents to the cheap providers?";
        recommended = "Raise within the card's limit; keep the guardrail.";
      };
      runner = {
        question = "Turn on the agents' runner on the host (each run spends credit)?";
      };
      gpu = {
        question = "GPU for trained models, images and video: serverless (about $20/month, a new card) or a dedicated server later?";
        recommended = "Serverless first.";
      };
      inventory = {
        question = "What goes into the twin's inventory first, and do photos stay in Proton Drive?";
      };
      trading-entity = {
        question = "Trade on the personal account or the LLC's?";
        answer = "The personal account (public-mirazo) for now (2026-11-07); the trader's tax status is the bank's to settle.";
      };
      wiring = {
        question = "Money wiring: which Mercury account funds Public, sweeps with a tap or by hand?";
      };
      trading-limits = {
        question = "Trading limits beyond the paper gate: seed, risk, margin, options level?";
      };
      owed-costs = {
        question = "When one entity pays another's costs (OpenRouter), record it as owed, or wait?";
      };
      kagamizo-purpose = {
        question = "What does Kagamizo become now that consulting is off?";
      };
      public-login = {
        question = "Move Public's sign-in to finance@mirazo.org, or change the declaration, before the exception ends on 2026-11-30?";
        answer = "Settle it (2026-11-07): move the sign-in onto its declared address before 2026-11-30; the owner approves the sign-in.";
      };
      publishing = {
        question = "Where research is published: arXiv (whose account), or self-hosted papers?";
      };
      records = {
        question = "Where formation documents and statements are kept: Proton Drive or a bucket?";
      };
      build-box = {
        question = "A self-hosted build machine (a priced Hetzner builder), once CI's times are measured?";
      };
      residence-state = {
        question = "Which state are you resident in (a comment in the repository says Texas)? It decides whether QSearch owes a franchise report and sales tax on research sold there.";
        answer = "Texas (2026-11-07). QSearch had no revenue, so nothing is owed there now; whether it must register or file Texas's franchise report once it earns is the lawyers' and accountants' question.";
      };
      mtm-election = {
        question = "Elect section 475(f) mark-to-market for 2027 (trader tax status), or not? The statement is due by 2027-04-15 and cannot be made late.";
        recommended = "Decide with the accountants once paper and live results show trading volume.";
      };
      crypto-venue = {
        question = "Open a crypto account for trading around the clock: Kraken (passkey or authenticator, keys that trade without withdrawals, a stable NautilusTrader adapter) or Coinbase? It is your sign-up; nothing is deposited until its paper days hold.";
        recommended = "Kraken.";
        answer = "Public's own crypto (2026-11-08): with Kalshi it covers every hour on the account already held; Kraken (chosen earlier the same day) is not needed for now, only for lower crypto fees or perpetual futures.";
      };
      ibkr-gateway = {
        question = "Run IBKR's Gateway on the host for futures across time zones (CME, Eurex, ICE Europe, Osaka, ASX) and forex: it signs in daily with the LLC's authenticator code, which would be held in Proton Pass for it. Allow that daily sign-in?";
      };
      canary = {
        question = "Place one real canary order to prove the live path end to end: an event contract limit far from the market (it should not fill), read back, then cancelled within the minute? Without it, place, read-back and cancel are proved only against the stub.";
        recommended = "Yes, once five paper days are in: a $0 expected cost, the owner approving it like any order.";
      };
      agent-mail = {
        question = "How agents send mail: Proton's business SMTP, or a Cloudflare-routed subdomain?";
      };
      spectrum = {
        question = "Pay for Cloudflare Spectrum so a game client reaches the world (later)?";
      };
      account-hub = {
        question = "Consolidate the bank's markets on as few accounts as possible: IBKR (the LLC's, already open: stocks and options here and abroad, futures on about 150 venues, forex, spot crypto, ForecastTrader event contracts, about 27 currencies in one account) plus Kraken for round-the-clock crypto and perpetuals, with Public kept only while its paper days run? It means trading through the LLC (still on your 1040, as QSearch is disregarded) and IBKR's daily Gateway sign-in.";
        recommended = "Yes, after Kraken's paper days: two accounts reach almost every market. No exchange membership or registration of our own adds anything at our scale: a clearing firm is still required, and trading our own money needs no broker-dealer registration.";
        answer = "Keep Public as it is (2026-11-08): it stays the trading account; no consolidation onto IBKR.";
      };
    };
  };
}
