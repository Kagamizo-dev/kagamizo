# design: a dashboard and report per account

Read CLAUDE.md first. Kind: page.

Every held account (`accounts.held`) gets its own page on the status page:
- its plan, capabilities with their sources, login and credential items;
- its grants: which team may read or write it;
- its lifecycles;
- its live numbers where a read exists: key spend (OpenRouter), card spend (Mercury), portfolio (Public), filing status (Northwest);
- a sign-in link that opens the provider's own login page, for the Proton Pass extension to fill.

The page never carries a credential.

The live numbers come from the nightly reads into one database: a single SQLite file on the host, schema declared in Nix, written by the Rust readers that already exist (money-ledger, cards, openrouter usage). The status Worker reads a JSON snapshot of it through the tunnel. Pages pass the page check at 390 and 1280 px.
