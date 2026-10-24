# Handoff

The state of the work on branch `ccr-a3dc11d9-lh43d5`, for the next session.
Read `CLAUDE.md`, `README.md` and the Gaps in `modules/cloudflare/README.md`
first; this file says where things stand and what comes next. Delete it once
its items are done.

## End of every session

The owner gets two things, each one code block to paste: the full
allowlist (one host per line, the whole list, only when it changed; the
environment's Network access → Allowed domains, with package managers
ticked) and the start message below, kept current.

Start message for the next session:

```
Continue the Kagamizo work on branch ccr-a3dc11d9-lh43d5. Read CLAUDE.md, README.md, the Gaps in modules/cloudflare/README.md, and HANDOFF.md first; HANDOFF.md's "The owner's standing decisions" holds what I've already decided, and its Roadmap is the order of work.

The network allowlist now has every host in HANDOFF.md's "The allowlist to apply": add them to modules/claude/_environment.nix first.

Start by signing the session in with `PROTON_PASS_KEY_PROVIDER=fs pass-cli login` and send me the approval link. Run no other pass-cli command until it returns.

Then roll the frozen environment out to every wrapper and add the Cedar closure policy (HANDOFF.md, "Where the 2026-10-23 session left it"), give mercury-jingzo an engine-held passkey of its own, then work the Roadmap from epic 2 on down.

The only thing you ask me for is approving a sign-in or 2FA link. Ask before anything else that spends money or applies infrastructure, unless HANDOFF.md says I already approved it. Every tool or API gets fully mapped from the pinned thing itself before it's used: Rust for what we write, Nix for packaging, Cedar for authorization, all in the one modules tree. End the session with the full allowlist (if it changed) and the updated start message, each ready to paste.
```

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

## The owner's standing decisions

- The owner's only manual step is approving 2FA or a sign-in link. Never
  hand them a form, a click-path, a value to copy or a command. The
  network allowlist (`modules/claude/_environment.nix`) is the one
  exception, since a session cannot change its own (it may not edit the
  declaration either until the owner has applied it); the hosts to apply
  next are listed below.
- Signups and card minting are the owner's (2026-10-24): the repo
  prepares a signup's login item (`signup prepare`) and declares a card
  as minted (`mercury.cards.<v>.nickname`), and `cards apply` is refused.
  Jingzo's Hetzner account (project "Default") is active and paid by the
  owner's Capital One virtual card locked to Hetzner, at a $7/month budget
  (`hetzner.payment`, `hetzner.monthlyBudgetUsd`); Mercury's "Hetzner"
  card ••7138 is no longer its payment.
- Ask before anything that spends money or applies infrastructure, unless
  the owner already said go. Already approved: the R2 build cache; the
  `move-login` exception; the Proton Pass renames (done); the $5 OpenRouter
  card once mercury-jingzo's login is finance@jingzo.org.
- The login rule stays strict, the card included: move a login before
  acting on its account.
- OpenRouter belongs to Kagamizo (the consulting side). Kagamizo is not
  formed yet, so a Jingzo card paying for it is a cost between the two
  companies: record it as owed by Kagamizo, or wait. Not decided yet.
- Every tool or API touched is first mapped in full, its options, types and
  auth extracted from the pinned thing itself (the catalogs), then wrapped:
  Rust for what we write, Nix for packaging, Cedar for who may act, all in
  the one modules tree. No guessed configuration.
- Kagamizo: consulting. Jingzo (QSearch LLC on paper): research, finance,
  quant trading. Mirazo: the owner, personal portfolio and retirement.
  Three GitHub organizations, one per identity.

## Where this session left it (2026-10-22)

- Proton Pass signed in (`pass-cli login`, approved).
- Mercury: `mercury:survey` mapped the sign-in page (Email, Password,
  "Log in", "Continue with passkey"). `mercury:invite-own-user` signs in
  with today's login and then explores (typed steps on stdin, same action
  and hosts), so one approval maps the signed-in pages. Its submitted
  sign-in failed with "We couldn't reach our servers": the allowlist lacks
  Mercury's API and device check. Nothing was approved or invited yet.
- Fixed on the way: a flow named after an effect shared its Cedar id with
  that effect's group and was denied (evaluation now fails on it); a text
  snapshot printed a field's typed value (never now; the check asserts
  it); the wrapper's cleanup raced Chromium and failed good runs.

## Where the 2026-10-23 session left it

- The allowlist from 2026-10-22 is applied and declared
  (`modules/claude/_environment.nix`); no new host was needed since.
- Epic 0: Cedar tests for every browser flow; `checks.catalog-coverage`
  (raw calls held to the catalogs, per-module report); Bridge cataloged
  from its pinned source (`modules/catalog/_json/bridge.json`). Still
  open: host maps from submitted sign-ins.
- Epic 1 done another way: the owner moved mercury-jingzo's login to
  finance@jingzo.org and saved two passkeys from the phone into
  `Jingzo-LLC / Mercury`. `mercury:passkey-sign-in` signs in with them (no
  password, no code; `login.passkey.source = "login-item"`), and
  `mercury-session --account mercury-jingzo` is signed in, its session in
  Jingzo-LLC-Sessions. Mercury's OAuth page was driven by hand through
  explore steps (account picker "QSearchLLC finance@jingzo.org", security
  key, "Authorize"): make `mercury-session login` run it as a flow.
- `mercury-cli`: the whole official CLI (71 commands of v0.11.8, the latest
  tag), each with a declared effect in `modules/mercury/commands.nix` (5
  excluded: login, logout, status, upgrade, onboarding apply); evaluation
  fails if the pinned CLI has a command with no effect. Cedar now tests
  every action of every provider (6126 tests). Read live for mercury-jingzo.
- The owner's pattern for every tool: map its full typed surface from the
  pinned thing first, then wrap it in Rust, Cedar, Lean 4 where a property
  is worth proving, and Nix. The browser only for sign-in and what has no
  API; each browser use backed by a REA model of the site. No account
  action before the surface is twinned.
- Mercury's twin: `catalog/_json/mercury-api.json` (from the pinned Go
  SDK) and `mercury/authorization.nix` (what the CLI's OAuth session may
  call, with evidence). Card management is in no documented tier for it,
  and POST /cards was refused (tokenNotAuthorized), so the $5 OpenRouter
  card (approved, declared on mercury-jingzo) is not issued. The ways to
  it: a Custom token with card scopes, which needs a fixed IP allow-list
  (the Hetzner host), or Mercury confirming what OAuth `write` covers.
  `mercury-cli` and `cards` are still shell; they become one Rust program.
- REA (`modules/rea`, morluto/rea at rea-agents-6.7.0) is built from
  source; its catalog (`catalog/_json/rea.json`: 207 MCP tools in 18
  families, 153 CLI commands) is checked in. Not yet wrapped in Cedar or
  used on a site.
- Epic 3 done: `modules/mailbox` (Bridge 3.24.2 headless, its vault and
  key in Mirazo-Root-Sessions, signed in as zach@mirazo.org; the Proton
  item's username and email were set to it with the owner's OK). The
  Mercury sender's link path is not mapped yet (`mailbox.senders.mercury
  .path`): the next device-check mail maps it.
- New: `modules/runtime` and `modules/_lib/frozen.nix`. The owner's rule
  is that nothing lives outside a Nix declaration: every wrapper runs from
  `env -i` with only declared variables (mailbox does; roll out to every
  wrapper next), and a Cedar policy will deny any action not running from
  its declared closure. The cloud container is an untrusted host; the
  Hetzner host becomes the first fully declared NixOS target.
- secretspec is built from its v0.21.1 tag with a patch
  (`modules/proton/_patches`): it gave pass-cli ids starting with '-' as
  separate arguments, so overwriting any secret failed. Worth sending
  upstream.
- **Passkey counter**: the engine's authenticator starts a loaded passkey's
  counter at the current Unix time, so Mercury now holds a counter far above
  what Proton Pass on the phone will send for the same passkey: the
  phone's passkey sign-in to Mercury (Jingzo) is likely refused from now
  on. The fix is for the engine to register a passkey of its own (source
  "engine"), and the phone to keep its own; until then the phone signs in
  with password and code.
- Cloudflare and Experian logins still use the old addresses; each needs
  its email changed at the provider first (a flow, now that mail is read).

## The allowlist to apply (one change, all of it)

Found on 2026-10-22 by loading every provider's sign-in page in the pinned
Chromium, recording every host it contacted (net log) and every host its
scripts name, and keeping the app's own hosts, its sign-in, its captcha and
payment where a flow pays (analytics, ads and Chromium's own calls left
out). `modules/claude/_environment.nix` already has the first two; the rest
go in once applied (the session may not widen its own allowlist).

| For | Hosts |
|---|---|
| Mercury's web app | `backend.mercury.com`, `fp.mercury.com`, `acdn.mercury.com`, `ldr.mercury.com` |
| Public's web app | `*.hellopublic.com`, `network.dv.socure.io`, `ingestion.dv.socure.us` |
| OpenRouter sign-in and top-up | `cdn.protect.clerk.com`, `js.stripe.com`, `api.stripe.com`, `m.stripe.network`, `hooks.stripe.com`, `checkout.stripe.com` |
| Northwest's portal | `ct-frontend.corporatetools.com` |
| GitHub's web flows | `octocaptcha.com`, `avatars.githubusercontent.com` |
| Experian's sign-in | `hcaptcha.com`, `*.hcaptcha.com` |
| Hetzner's console | `console.hetzner.cloud`, `console.hetzner.com` |
| Gitea, Substack | `gitea.com`, `substackcdn.com` |
| The outlook mailbox (moving a login confirms at the old address) | `login.live.com`, `account.live.com`, `outlook.live.com`, `login.microsoftonline.com`, `outlook.office365.com` |

Already covered: Proton (`*.proton.me`, Bridge included), IBKR
(`*.interactivebrokers.com`), Cloudflare's Turnstile, R2
(`*.r2.cloudflarestorage.com`, in the defaults). Hosts seen only after a
sign-in are found by the flows' explore runs; each is added the same way.

## Roadmap

ETAs are working time for a session once nothing blocks it; "you" is the
owner's part, always an approval. Order is the order of work.

| # | Epic | Stories | Blocked on | You | ETA |
|---|---|---|---|---|---|
| 0 | **Validate before acting** | Host map per provider from a submitted sign-in (explore runs); a Cedar test for every flow (allowed for the controller under its effect, denied to agents); every tool and API checked against its pinned catalog, with a coverage report per module | the allowlist above | — | 3 h |
| 1 | **Mercury, Jingzo's own login** | Explore the signed-in pages; invite finance@jingzo.org (team settings); its passkey (after an authenticator-app 2FA); login item in Jingzo-LLC; `login.passkey.rpId`; `mercury-session --account mercury-jingzo login` | the allowlist | sign-in approval; Mercury link; the invite mail until epic 3 | 2 h |
| 2 | **$5 OpenRouter card** | `mercury.account = "mercury-jingzo"`, `cards plan`, `cards apply` | 1; how to record it between Jingzo and Kagamizo (owed, or wait) | that decision | 30 min |
| 3 | **Confirmation mail** | Bridge headless under Nix, its login driven from Proton Pass; a Rust IMAP reader (declared addresses, declared senders, links on the flow's hosts only); then the outlook mailbox the same way | — | one Proton sign-in approval | 6 h |
| 4 | **Build cache and CI** (approved) | R2 bucket in the Cloudflare module, signing key in Proton Pass, CI pushes and machines pull; `nix flake check` one job per check; Rust with crane | — | — (a Gap if R2 is not enabled) | 5 h |
| 5 | **Every login onto its domain** | One flow each, passkeys where offered: Northwest, Public, Cloudflare, Experian, IBKR (two), GitHub, Gitea; the outlook Email retired last | 0, 3 | a sign-in approval each | 1 h each, ~1.5 days |
| 6 | **Public** | public-mirazo's login item and personal secret through the browser; whether the API may serve an LLC's account | 5 | the terms question | 2 h |
| 7 | **OpenRouter** | Signup (passkey), first top-up from the card, management key, `openrouter apply` mints the capped keys | 2 | approvals | 2 h |
| 8 | **Northwest** | Its portal through the flows (or its connector in Claude); `northwest catalog` from the server; Jingzo's state, formation date, EIN into `modules/identity/jingzo.nix` | 5 | sign-in approval | 4 h |
| 9 | **Legal module** | Catala: §475(f) election and revocation, Wyoming annual report and license tax, estimated tax dates; pinned eCFR Title 26 and US Code | — | — | 2–3 days |
| 10 | **Kagamizo LLC** | Formation and EIN through Northwest; Mercury's business application; its own cards | 8 | signature and SSN in Northwest's portal (a Gap); the pay link | 1 day of work, weeks of state and IRS time |
| 11 | **The host and swarms** | Hetzner (signup is ID and selfie, a Gap; console behind proof-of-work), Open WebUI, OpenCode, Bridge on a private domain; agents' audit record | 3, 7 | Hetzner's ID check | 2–3 days |
| 12 | **Trading live** | Public adapter's first real run, live as a governed spend action, IBKR as a second backend | 6, 9 | — | 2–3 days |
| 13 | **The PR into `main`** | Review, CI green | when you ask | — | 1 h |

Total before the PR: about 2 weeks of session time, with Kagamizo's
formation running on the state's and the IRS's clocks in parallel.

## Next

1. **Sign the session in**: `PROTON_PASS_KEY_PROVIDER=fs pass-cli login`,
   send the owner the link, and run no other pass-cli command until it
   returns (a concurrent call corrupted the session store once).
2. Once the allowlist above is applied: add its hosts to
   `modules/claude/_environment.nix`, then work the roadmap from epic 0.
   Mercury: `tail -f steps.jsonl | nix run .#browser -- --account
   mercury-jingzo mercury:invite-own-user`, append typed steps
   (`{"do":"snapshot","text":true}` reads the page's words), and write what
   the exploring shows into the flow's declared steps.

Leftovers: six old swarm agents (`swarm-*-qsearch`, `swarm-*-zachariah`)
and their token items in Mirazo-Root; deleting them was refused by the
permission check, and they expire on 2026-11-21.

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
