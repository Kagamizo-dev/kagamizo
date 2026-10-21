# Identity as code: Cloudflare and Proton Pass

The domains, the mailboxes on them, the Cloudflare account and the Proton Pass
vaults are all declared in Nix under `modules/`, type-checked with
[nix-effects](https://github.com/kleisli-io/nix-effects), rendered to OpenTofu
JSON, and changed only through a reviewed plan. Secrets are never in this
(public) repo: `secretspec.toml` names them, Proton Pass holds them.

## Accounts and plans

Each provider's module declares its account, the plan it is on and what that
plan includes, with the provider's page as evidence (`modules/<provider>/account.nix`);
`modules/accounts/` types and checks them. Modules declare what they need as
`accounts.demands`, e.g. one Proton custom domain per domain with mailboxes;
evaluation fails, naming the plan and its source, if a plan does not cover it.

## Layout

The repo's layout (one `modules/` tree, each module a self-contained unit) is
described in the [top-level README](../../README.md#layout).

## Catalogs: what each tool can do, typed

Nothing about a CLI or the provider is guessed. `modules/catalog/_json/` holds
what each pinned tool can do, extracted from the tool itself (`modules/catalog/`):

| Catalog | From | Holds |
| --- | --- | --- |
| `cf.json` | cf's own metadata | every command: arguments (variadic or not), options and body fields with types and required, the API call; cf's OAuth scopes |
| `cloudflare-provider.json` | `tofu providers schema -json` | every resource and data source, per attribute: type, required, optional, computed |
| `pass-cli.json` | pass-cli's help tree | every command, its arguments and options |

`modules/_lib/cli.nix` types every use against them: `cli.cf`, `cli.passCli` and
`cli.tofu` reject an unknown command, option, resource or attribute, a missing
required one, or a wrongly typed value, naming the field, before anything
runs. OAuth scopes in `login.nix` must be cf's. Bumping a tool changes its
catalog, so an upgrade is a reviewable diff, and `nix flake check` fails until
the committed catalog matches the pinned tool (`nix run .#catalog-update`).

## The model

An **entity** (a person, an LLC, a nonprofit) owns **domains**, and each domain
has **at most seven mailboxes**. An eighth means a new domain. Mailboxes are
roles (`admin`, `billing`, `legal`, ...); per-service addresses are Proton Pass
aliases on the domain and don't count. Which service uses which address lives
in the entity's Proton Pass vault, never in git.

The types enforce this at eval time, and each failure names its field:

- a domain must belong to a declared entity (the type of `domains` depends on
  the value of `entities`);
- a domain without a `zoneId` can't carry DNS (its `proton` and `records`
  types depend on its own `zoneId`);
- mailbox names, domain names, Cloudflare IDs and vault names are refined
  strings.

## Secrets: declared refs, values in Proton Pass

Infrastructure changes are OpenTofu plans, code changes are git diffs, and
secret changes are diffs of references: `secretspec.toml` (generated from
`modules/proton/secretspec.nix`) names every secret by vault and item title,
Proton Pass holds the value, and `proton plan` shows which references exist
and which are missing. Values never pass through git, and every vault opens
only through a Proton login carrying your 2FA.

A secret lives with the identity it belongs to, and the types enforce which
vault can be which:

| Vault | Holds | Must be |
| --- | --- | --- |
| `Zachariah-Root` | your own logins; no Cloudflare credential (the root is your OAuth session) | a person's vault |
| `Kagamizo-LLC` | Kagamizo's own credentials: its GitHub organization, its logins | an LLC's or nonprofit's vault |
| `Kagamizo-CI` | `ci-apply` token | CI only |
| `Kagamizo-Agents` | `agent-readonly` token, OpenRouter key | agents only |
| `Kagamizo-State` | the encrypted OpenTofu state and its passphrase | CI as `editor`, plans and agents as `viewer` |

Account-wide power (minting tokens, buying domains) is never stored: it is
your `cloudflare-login` session, approved on your phone behind Cloudflare's
2FA, and it dies with the container.

Every credential is a view. A Proton Pass agent token opens exactly one vault,
and secretspec turns a vault into the same environment variables every time,
so what a process can do depends only on which vault it was given.

| Role | Vault | Cloudflare token | Can |
| --- | --- | --- | --- |
| You (`bootstrap`) | none | OAuth session | mint the tokens below |
| You (`registrar`) | none | OAuth session | buy domains, within budget; read zones |
| CI on `main` | `Kagamizo-CI` | `ci-apply` | apply merged changes |
| Agents, PR plans | `Kagamizo-Agents` | `agent-readonly` | read everything, change nothing |

Vault names are declared once, in `modules/proton/vaults.nix`.

## Commands

```bash
nix run .#cloudflare-login                                 # OAuth session: a link you approve
nix run .#bootstrap -- <plan|apply|rotate <name>>          # mint the tokens
nix run .#infra -- <ci|agent> <tofu args...>               # OpenTofu, as that view
nix run .#registrar -- check                               # price every candidate
nix run .#registrar -- register <domain> <price>           # buy one (billed, budgeted)
nix run .#registrar -- zone <domain>                       # its zone ID
nix run .#registrar -- ledger                              # live registrations not declared
nix run .#proton -- plan                                   # vaults, agents, secret refs: the diff
nix run .#proton -- apply                                  # create vaults and agents, grant access
```

`infra` resolves its view's secrets itself (`infra agent plan`); the state is
a local file it fetches from `Kagamizo-State` and, under `ci`, writes back when
the run changed it. `bootstrap` and `registrar` use your `cloudflare-login`
session. In cloud sessions all of them are on PATH
(`.claude/hooks/session-start.sh`).

## Day to day, from the phone

1. Ask an agent for a change (a mailbox, a record, a token permission).
2. It edits the declarations and opens a PR.
3. The `infra` workflow posts a plan made with the read-only view. Read it in
   the GitHub app.
4. Merge. The `apply` job applies it with the `ci-apply` view.

Changes to `tokens.nix` only take effect when you run `bootstrap apply`; CI
cannot mint tokens.

**Kill switch:** `pass-cli agent delete <name>` cuts an agent token off
immediately. To kill Cloudflare access too, delete the token on the dashboard
(Manage Account, Account API Tokens).

## Spending limits

Every paid resource gets a declared limit, checked before anything is spent.
Cloudflare has no spending cap of its own (its budget alerts only send an
email), so `cloudflare.monthlyBudgetUsd` (in `account.nix`, 40 USD) is enforced
here, twice:

- **In the types.** Each domain bought through Cloudflare records its
  `registration = { month; costUsd; renewalUsd; }`. Eval fails if any month's
  purchases plus that month's renewals exceed the budget, naming the month.
- **At purchase.** `registrar register` adds this month's purchases and
  renewals from that ledger to the price and refuses to buy over the budget.

Only your `cloudflare-login` session can buy domains (account tokens cannot
hold Registrar), so every purchase goes through this check and your
Cloudflare 2FA. The ledger only knows what is declared, so record each
purchase right away; the command prints the lines to add.

## Adding a domain

1. Add names to the entity's `domainCandidates` and run `registrar check`.
2. Pick one. `registrar register <domain> <price>` buys it only if `<price>` is
   exactly the current registration cost and the month stays within budget, so
   nothing is charged by accident. Registrations are non-refundable.
3. Declare it under `identity.domains` with `registrar = "cloudflare"`, the
   `registration` lines the command printed, its mailboxes, and its `zoneId`
   from `registrar zone <domain>`. Run `bootstrap apply` so the ci and agent
   tokens cover the new zone.
4. In Proton: Settings, Domain names, add it. Copy the verification value and
   DKIM ID into the domain's `proton` field; the next apply publishes MX, SPF,
   DKIM and DMARC. Then create the mailboxes in Proton, one per declared name.

Proton has no API for domains or addresses, so step 4's Proton side is manual.

## Claude sessions

`.claude/settings.json` runs `.claude/hooks/session-start.sh` in cloud
sessions, which builds `.#session-tools` (pinned `pass-cli`, `secretspec` and
the three apps above) and puts it on PATH.

The session's network allowlist is declared, type-checked, in
`modules/claude/_environment.nix`. It cannot apply itself, so paste it once:
cloud environment menu, Edit, Network access **Custom**, tick *Also include
default list of common package managers*, and paste the output of
`nix build .#claude-allowed-domains && cat result` into Allowed domains.

## One-time setup

Done already: account and zone IDs, and the first four vaults.

Your part is approvals only: a link for Cloudflare, a link for Proton Pass.

1. **Sign in.** `cloudflare-login` and `pass-cli login`, each a link you
   approve on your phone.
2. **Proton.** `proton apply` creates `Kagamizo-State` and the three agents in
   `agents.nix`, stores each agent token in `Zachariah-Root` (profile
   `proton-agents`) and grants the declared roles.
3. **Cloudflare.** `bootstrap apply` generates the state passphrase into
   `Kagamizo-State` and mints `ci-apply` and `agent-readonly` into their
   vaults. If it names a permission group Cloudflare does not offer account
   tokens, fix the name in `tokens.nix`. `proton plan` then shows every
   reference as `ok` (`tofu-state` stays optional until the first apply).

   Re-run `bootstrap apply` after changing `tokens.nix` or `tokenExpiry`: it
   updates existing tokens in place, keeping their values. `bootstrap rotate
   <name>` replaces one value.
4. **Existing records.** OpenTofu only manages what it created. Before
   declaring a record that already exists, import it with the ci view, since
   import writes state. Resource names are prefixed with the zone:

   ```bash
   nix run .#infra -- ci import 'cloudflare_dns_record.kagamizo-com-www' '<zone id>/<record id>'
   ```

## Gaps: anything that takes more than a 2FA approval

The rule for this repo: the only thing you ever do by hand is approve 2FA.
Each item below breaks that rule today and is to be closed, not documented
around.

- **The GitHub organization itself**: github.com has no API to create one;
  `signup` prepares it from Proton Pass. Everything after (repos, secrets,
  environments, domain verification) is `modules/github`, applied by the
  `github-bootstrap` workflow, since cloud sessions cannot reach org APIs.
- **The Claude GitHub app on the organization**: a cloud session reaches
  only repos the app is installed on, and installing it on a new org is a
  page on github.com, not an API. Until then a session cannot follow
  `github-bootstrap`'s transfer of a repo into the org.
- **Hetzner and OpenRouter signups** (`signup plan`): web-only. Hetzner
  checks a government ID and a selfie, and its first project API token is made
  in the Cloud Console; OpenRouter's first management key (saved as
  `Kagamizo-LLC/openrouter-management-key`) and first credit top-up are made
  in its dashboard. After those, `hcloud`, OpenTofu and the
  `openrouter` wrapper do everything.
- **Kagamizo's Mercury account** is not open yet (`signup plan`): Mercury's
  business application is web-only and checks the EIN letter, formation
  documents and the owner's ID. The vendor cards wait for it; they are not
  issued from a personal account.
- **Mercury** needs no dashboard token: `mercury-session login` runs the
  official CLI's OAuth sign-in, an approval link. Approving on a phone leaves
  a failed 127.0.0.1 page whose address is handed back to the waiting login.
  Entering a card on a vendor's billing page is manual wherever Mercury will
  not reveal it into Proton Pass.
- **Northwest's tool catalog** (`modules/northwest/_json/tools.json`) is a
  seed of the 19 tool names on Northwest's tools page, of the 131 it states.
  `northwest catalog` replaces it with the server's own tools/list once
  `northwest login` has run, and every new tool then needs an effect in
  `modules/northwest/tools.nix` before anything can call it. The session's
  network allowlist must include Northwest's hosts first (below).
- **Northwest's OAuth client for the CLI**: Northwest documents the public
  `mcp-connector` client for AI clients with manual OAuth settings, not a
  loopback redirect for a CLI. `northwest login` registers its own client
  when the identity server allows dynamic registration and otherwise falls
  back to `mcp-connector`; whether either accepts a 127.0.0.1 redirect is
  untested until the first login.
- **Public's personal secret** (`Zachariah-Root/public-personal-secret`) is
  made in its settings, and funding Public has no API at all: deposits are
  started from Public's side.
- **Proton Mail domains and addresses** are added in Proton's web settings
  (account.proton.me, any browser; not the mobile app): Proton has no public
  API for them, and its internal one only admits Proton's own clients. Each
  new domain's verification and DKIM values are then read off that page into
  `identity.domains.<d>.proton`, and OpenTofu publishes the records.
- **Proton Mail's API is Proton's internal one.** Proton publishes no API for
  domains or addresses, so `mail` uses the one its own clients use, through
  its go-proton-api; signing in takes your 2FA code (and a verification link
  if Proton asks for one). It is a gap in the sense that Proton could change
  it without notice.
- **Registrar prerequisites**: default payment method, registrant contact and
  the registration agreement, dashboard only.
- **The session's network allowlist** (`modules/claude/_environment.nix`):
  cloud environment settings cannot be changed from inside a session.

## The agent fleet (Orca)

[Orca](https://github.com/stablyai/orca) runs the agents on a computer and its
mobile app steers them. Give the fleet the agent view by signing in with the
`orca-fleet` token and starting Orca under secretspec, so every agent it
launches inherits `OPENROUTER_API_KEY` and the read-only `CLOUDFLARE_API_TOKEN`:

```bash
export PROTON_PASS_SESSION_DIR=$HOME/.pass-orca-fleet
pass-cli info >/dev/null 2>&1 || PROTON_PASS_PERSONAL_ACCESS_TOKEN=pst_... pass-cli login
nix run .#orca-fleet
```

`orca-fleet` runs Orca under the `agent` profile, so its agents hold the
fleet's own OpenRouter key (`openrouter.keys.orca-fleet`, capped per month),
and OpenCode starts on `deepseek/deepseek-v4-flash` (`packages.opencode-config`).

Agent sessions last two hours, after which `pass-cli login` has to run again.
Agents then change infrastructure the same way you do: by opening a PR.

## The legal, accounting and governance swarms

`modules/governance` declares who may do what and compiles it to Cedar:
people control entities (`governance.controllers`), every wrapper operation
is an action typed by its effect (read, write, spend, destroy, session), and
each agent serves exactly one entity with only the grants listed. Three
swarms per entity (legal, accounting, governance) run agency-agents personas
as OpenCode subagents:

```bash
nix run .#orca-swarm -- legal-qsearch
```

The base policies hold whatever the grants say: an agent never spends,
destroys or signs in, and never reaches another entity's accounts. Each
swarm has its own Proton Pass agent token (`swarm-<name>`), opening only its
entity's sessions vault (`<Vault>-Sessions`); that is the hard boundary,
and Cedar is what the wrappers check (`governance-authorize`) inside it.
`nix flake check` validates the policies against the schema and runs tests
derived from the declarations, each naming the policy that must decide it.

## Not covered yet

- Cloudflare Tunnel and Access (for God's Eye View on the Pi), Workers and
  Pages: the tokens already allow them; add the resources to `_zones.nix`.
