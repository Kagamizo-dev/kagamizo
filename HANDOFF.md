# Handoff

The state of the work on branch `ccr-a3dc11d9-lh43d5`, for the next session.
Read `CLAUDE.md`, `README.md` and the Gaps in `modules/cloudflare/README.md`
first; this file says where things stand and what comes next. Delete it once
its items are done.

## A new cloud environment

Network access: **Custom**, with "Also include default list of common package
managers" ticked, and these allowed domains (`nix build
.#claude-allowed-domains` prints the current list):

```
*.proton.me
proton.me
api.cloudflare.com
dash.cloudflare.com
api.mercury.com
oauth2.mercury.com
vault-api.mercury.com
api.public.com
openrouter.ai
mcp.northwestregisteredagent.com
id.northwestregisteredagent.com
www.northwestregisteredagent.com
```

Then sign the session in: `pass-cli login` (an approval link). Cloudflare's
root session (`cloudflare-login`, a device code, 5 minutes) is only needed for
`registrar` and `bootstrap`; DNS applies run on the stored CI token.

## Where each identity stands

`nix run .#identity-status` prints this live.

| | Kagamizo LLC | QSearch LLC | Zachariah (person) |
|---|---|---|---|
| Legal | planned, Wyoming, EIN none | active; state, date, EIN unknown | natural |
| Domain | kagamizo.com, mail live | jingzo.org, DNS complete; Proton verify pending | — |
| Registered agent | northwest-kagamizo, planned (login item ready) | northwest-qsearch, active, not signed in yet | — |
| Bank | mercury, planned (needs the LLC and EIN) | mercury-qsearch, active, no session or cards here yet | — |
| Brokerage | — | — | public, active; personal secret missing (a Gap) |
| Other | github active; hetzner, openrouter planned | arxiv-qsearch planned (paused) | proton, cloudflare active |

Proton Pass has every entity's vault plus a `<Vault>-Sessions` vault each, and
nine swarm agent tokens (legal, accounting and governance per identity) in the
root vault.

## Next, in this order

1. **Mercury, solid first.** Kagamizo's own Mercury waits on formation and the
   EIN (days to weeks), but QSearch's account exists today. Make
   `mercury-session` per account, like `northwest` (one profile per held
   Mercury account, its session in the owner's sessions vault), sign
   `mercury-qsearch` in, and give its swarms read grants (`cards-funds`,
   `cards-spend`). Decide with the owner whether vendor cards come from
   QSearch's account until Kagamizo's opens, or wait.
2. **Public.** Its personal secret is made once in Public's settings (a Gap);
   then `brokerage summary` works for the owner. No swarm gets it: the secret
   trades as well as reads.
3. **OpenRouter.** Sign up as dev@kagamizo.com (login item ready), first
   top-up and management key in its dashboard (Gaps), then `openrouter apply`
   mints the five capped keys (host, fleet, one per identity's swarms). The
   card for it comes from step 1.
4. **Northwest.** `northwest login` for `northwest-qsearch` (one approval
   link), then `northwest catalog > modules/northwest/_json/tools.json` and type
   every new tool's effect in `modules/northwest/tools.nix`. Read QSearch's
   state, formation date and EIN status off `get_company_details_tool` into
   `modules/identity/qsearch.nix`. Kagamizo's formation order follows once its
   own Northwest account exists.
5. **Agents to work.** With models (3) and accounts (1, 4) in place, run the
   swarms (`nix run .#orca-swarm -- <name>`) and start assigning work. The
   always-on host (Hetzner: Open WebUI, OpenCode, Proton Bridge) is the
   previous session's tasks 4 and 5.
6. **The PR** from this branch into `main`, once the owner asks; the branch
   is green (`nix flake check`, everything but the VM and image builds run
   here).

## Paused

arXiv (`arxiv-qsearch`, planned, login item ready): paused by the owner.

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
