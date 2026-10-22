# Handoff

The state of the work on branch `ccr-a3dc11d9-lh43d5`, for the next session.
Read `CLAUDE.md`, `README.md` and the Gaps in `modules/cloudflare/README.md`
first; this file says where things stand and what comes next. Delete it once
its items are done.

## A new cloud environment

Network access: **Custom**, with "Also include default list of common package
managers" ticked, and the allowed domains `nix build .#claude-allowed-domains`
prints (declared in `modules/claude/_environment.nix`, one group per purpose:
providers' APIs, the browser flows' web apps, the legal corpus).

Then sign the session in: `pass-cli login` (an approval link). Cloudflare's
root session (`cloudflare-login`, a device code, 5 minutes) is only needed for
`registrar` and `bootstrap`; DNS applies run on the stored CI token.

## Names

Three identities, each named after its domain: **Mirazo** (Zachariah, the
person, mirazo.org), **Jingzo** (QSearch LLC on paper: the EIN, Northwest,
the state; jingzo.org) and **Kagamizo** (Kagamizo LLC, kagamizo.com). The
entity ids are `mirazo`, `jingzo`, `kagamizo`. Proton Pass's vaults carry the
new names (Mirazo-Root, Jingzo-LLC and their -Sessions vaults), and the
swarms' agents are `swarm-*-jingzo` and `swarm-*-mirazo`. The six old agents
(`swarm-*-qsearch`, `swarm-*-zachariah`) and their token items in
Mirazo-Root are still there, unused: deleting them was refused by the
session's permission check, and they expire on 2026-11-21.

## Where each identity stands

`nix run .#identity-status` prints this live; `nix run .#identity-audit`
holds every login against Proton Pass.

| | Kagamizo LLC | Jingzo (QSearch LLC) | Mirazo (Zachariah) |
|---|---|---|---|
| Legal | planned, Wyoming, EIN none | active; state, date, EIN unknown | natural |
| Domain | kagamizo.com, mail live | jingzo.org, mail live | mirazo.org, mail live (zach@, automations@; more as Pass aliases) |
| Registered agent | northwest-kagamizo, planned | northwest-jingzo, active; login on qsearchllc_wy@outlook.com; CLI cannot sign in | — |
| Bank | mercury, planned (needs the LLC and EIN) | mercury-jingzo, active, not signed in; holds the $5; login is the person's passmail alias | mercury-mirazo, active, signed in (Mirazo-Root-Sessions), $0; login a passmail alias |
| Brokerage | — (none needed) | public-jingzo, active; login on the outlook address; its API not relied on (terms) | public-mirazo, active; no login item in Pass; personal secret missing |
| Credit | — (D-U-N-S once the EIN exists) | — (D-U-N-S) | experian, active; login still zachary.oshodi@outlook.com |
| Other | github active; hetzner, openrouter planned | arxiv-jingzo planned (paused; likely self-hosted papers and Substack instead) | proton, cloudflare active; both log in as zachariah.oshodi@protonmail.com |

Every login in Jingzo's vault is on qsearchllc_wy@outlook.com, and the
vault holds logins no account declares yet: Email (that outlook address),
IBKR (two), Github, Gitea, Arxiv. Kagamizo's holds Proton and
MirrorConsulting, also undeclared.

Proton's plan is full: 3 of 3 custom domains, 15 of 15 addresses; any further
address is a Proton Pass alias. Proton Pass has every entity's vault plus a `<Vault>-Sessions` vault each, and
nine swarm agent tokens (legal, accounting and governance per identity) in the
root vault.

## Next, in this order

1. **Logins onto their domains.** governance-authorize now refuses any
   account whose Proton Pass login is not its declared address on its
   owner's domain, the card included (the owner's call). Per account, the
   provider's email moves (its settings, a Gap), then the Pass item is
   updated to match, then `identity-audit` shows ok. First: Jingzo's own
   Mercury user on finance@jingzo.org, then `mercury-session --account
   mercury-jingzo login`.
2. **The $5 OpenRouter card** from mercury-jingzo once it is signed in:
   `mercury.account` to mercury-jingzo and the OpenRouter card at $5
   (both waiting on the owner: which entity owns OpenRouter, since the card
   is Jingzo's and the account is declared Kagamizo's).
3. **Proton Pass renames** (vaults, agent tokens) to the new names, on the
   owner's go; then `proton plan` shows nothing to do.
4. **Public.** public-mirazo's login item and personal secret (Gaps); then
   `brokerage summary`. public-jingzo waits on the API terms question.
5. **OpenRouter.** Signup, first top-up and management key (Gaps), then
   `openrouter apply` mints the capped keys.
6. **Northwest.** `northwest login` cannot sign in: dynamic registration is
   refused (403) and `mcp-connector` rejects a 127.0.0.1 redirect (a Gap).
   Northwest's documented path is a custom connector in Claude
   (claude.ai/customize/connectors); a session started after it is added
   reaches the tools directly. Then: the server's tools/list into
   `modules/northwest/_json/tools.json`, every new tool's effect in
   `modules/northwest/tools.nix`, and Jingzo's state, formation date and
   EIN status off `get_company_details_tool` into
   `modules/identity/jingzo.nix`.
7. **The host** (Hetzner: Open WebUI, OpenCode, Proton Bridge on a private
   domain), then the swarms at work. Agents are denied by the login rule
   until they can read an audit record (a Gap).
8. **The PR** from this branch into `main`, once the owner asks.

## Paused

arXiv (`arxiv-jingzo`, planned, login item ready): paused; the owner leans
toward self-hosted papers, GitHub and Substack instead.

## How much of each lifecycle is CLI

### Northwest (MCP server, `northwest`)

From Northwest's tools page, read through search results (no sign-in): 130
of its 131 tools are in `modules/northwest/_json/tools.json`, each typed in
`modules/northwest/tools.nix` (68 read, 41 write, 17 spend, 4 destroy).
`northwest catalog` replaces the list with the server's own once signed in;
some clients see the names with a `v2__` prefix, which the catalog will show.
OAuth: Keycloak realm `northwestregisteredagent.com` on
id.northwestregisteredagent.com (`/auth/realms/...`), public client
`mcp-connector` with PKCE; whether it takes a 127.0.0.1 redirect or offers
dynamic registration is settled by the client's discovery on first login.

| Stage | CLI | How |
|---|---|---|
| Open the account | no | web signup; `create_company_tool` needs an account |
| Form the LLC | mostly | `company_entity_catalog`, `create_company`, `list_formation_filing_options`, `add_formation_to_cart`, checkout; the form's signature, dates and SSN are typed in the portal |
| EIN | partly | `list_ein_filing_options`, `add_ein_to_cart` (an SSN flag only), checkout; `get_company_ein` reads it back; SSN and signature in the portal |
| Annual reports | read, plus auto-filing | `get_annual_reports` (due dates, autopay); `purchase_compliance_service` starts the free renewal filing service |
| Amendments | yes, with form limits | `list_amendment_filing_options`, `add_amendment_filing_to_cart`, the form tools |
| Company record, standing | yes | details, EIN, state status, action items, orders needing attention |
| Documents | yes | list, details, text of unlocked ones (not legal documents), unlock invoice, mailed copies; legal originals download in the portal |
| Invoices, payments | partly | pay with a saved method, autopay, refunds, pay links; adding a method is the portal |
| Registered agent, mail | yes | services, status, mail plans, RA in a new state (`add_ra_service_to_cart`), cancel |
| Email, phone, domains, DNS | yes | not used: Proton holds mail, Cloudflare the domains |
| Operating agreement, foreign registration, dissolution | unknown | no tool by name; maybe products (`discover_products`), else the portal |

Northwest's own limits: no card or SSN in chat; payment is a saved method or
a texted pay link; write tools run only after an approval in chat, some only
for the account owner.

Documents stay at Northwest. The repo keeps pointers only: an index item per
entity in its Proton Pass vault (`northwest-documents`: Northwest's company
and document IDs, titles, dates), written from `get_documents_tool`, since
titles can be sensitive (service of process) and the repo is public. Make it
a `northwest documents` command once the tool's output shape is known.

### Public (`brokerage`, pinned CLI v1.3.7)

Read from the CLI's generated API client; every endpoint it has is wrapped
and typed (`modules/public/actions.nix`):

| Stage | CLI | How |
|---|---|---|
| Open the account, fund it | no | app only; deposits and withdrawals have no API |
| Personal secret | no | made once in settings (a Gap); tokens are minted from it |
| Accounts, portfolio, buying power | yes | `accounts`, `portfolio show` |
| Market data, options, bonds | yes | quotes, bars, chains, greeks, bond details |
| Orders | yes | preflight, place, multi-leg, replace, cancel, search |
| History | yes | trades, deposits, withdrawals, dividends, interest, fees (read only) |
| Tax | partly | unrealized tax lots (also CSV); no 1099s or statements |

No token scopes: a token minted from the secret can always trade
(`accounts.plans.public.individual.capabilities.scopedSecrets = false`).
So agents still get no brokerage access, and the API stays personal: it is
for personal, non-commercial use, never the LLCs'.

## Trading (`modules/trading`)

NautilusTrader 1.231.0 (the last stable; 2.x is a release candidate) is
packaged from its wheel, and `trade backtest <strategy> <bars.csv>` runs a
declared strategy; `checks.trading-backtest` proves the engine trades end to
end. Brokerages are backends (`trading.backends`), Public first, at stage
`backtest`. Next:

1. **The Public adapter**, ours (NautilusTrader has none): paper is in
   (`modules/trading/_public.py`: token, bars, preflight; `trade paper`), and
   `checks.trading-backtest` drives it against a stand-in. Its first real run
   waits on Public's personal secret (Next 2). Placing, replacing, cancelling
   and order status come with live (3).
2. **`trade bars`**: in; Public's bars into the backtest CSV, through
   governance-authorize under the public profile.
3. **Live** as a `trading` governance action with effect spend: only a
   controller places orders; agents backtest and paper-trade.
4. **The account question for the legal swarm**: Public now opens business
   accounts for single-owner LLCs, but its Individual API terms say personal,
   non-commercial use and forbid wrapping the API; nothing found addresses
   the API on a business account. Settle it, ideally in writing from Public,
   before an LLC's account trades through it. Funding is a deposit started
   from Public's side, from the entity's own Mercury account.
5. **IBKR** as a second backend (NautilusTrader's adapter; corporate accounts).

## Research to do: closing the Gaps

A pass through open-source projects for each remaining manual step, recorded
as findings on the accounts they concern:

- **Confirmation mail for agents.** Proton Bridge (official, IMAP/SMTP on the
  host) so an agent reads only its own role address; check that Bridge runs
  headless under NixOS and how to scope one mailbox per agent.
- **Web signups and dashboards** (Northwest, Mercury's application, OpenRouter,
  Hetzner, arXiv): browser automation (Playwright, which this environment
  ships) driven from declared signups, with the human step reduced to 2FA.
  Each provider's terms on automated signup must be read first.
- **Documents.** Northwest keeps served documents and filings in its portal
  (readable through its MCP tools). Long-term storage of formation documents,
  the EIN letter and statements: Proton Drive (rclone has a community
  `protondrive` backend; unofficial) or a declared bucket. Decide and type it
  as a slot ("records").
- **Proton Mail domains.** Still web-only: Proton's API refuses clients that
  are not Proton's own (Invalid section name, code 2064), and the repo will
  not pose as one.

## Open questions for the owner

- **arXiv account owner.** arXiv accounts belong to people, not companies:
  authors register as themselves and give an affiliation. The cleaner model
  is the account on Zachariah (the author), with affiliation QSearch LLC. The
  email can stay research@jingzo.org, or be a personal one. An `.edu` address
  would not avoid endorsement: since 2026-01-21 an institutional address only
  counts together with prior papers in the same domain.
- **Northwest** forms in Wyoming online; nothing is filed in person. The EIN
  can be ordered with it, or taken free from the IRS online after the LLC
  exists.
