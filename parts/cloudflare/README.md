# Identity as code: Cloudflare and Proton Pass

The domains, the mailboxes on them, the Cloudflare account and the Proton Pass
vaults are all declared in Nix under `parts/`, type-checked with
[nix-effects](https://github.com/kleisli-io/nix-effects), rendered to OpenTofu
JSON, and changed only through a reviewed plan. Secrets are never in this
(public) repo: `secretspec.toml` names them, Proton Pass holds them.

## Layout

Every `.nix` file under `parts/` is a flake-parts module (the dendritic
pattern, loaded by import-tree); files starting with `_` are helpers.

```
parts/
├─ _lib/types.nix          the identity model as nix-effects types
├─ identity/
│  ├─ options.nix          identity.entities / identity.domains
│  ├─ kagamizo.nix         Kagamizo LLC, kagamizo.com and its mailboxes
│  ├─ qsearch.nix          QSearch LLC and its domain candidates
│  └─ check.nix            `nix flake check` type-checks all of it
├─ cloudflare/
│  ├─ account.nix          account ID, state bucket, token expiry
│  ├─ tokens.nix           the API token profiles (views)
│  ├─ _bootstrap.nix       layer 1: mints tokens.nix          (you, by hand)
│  ├─ _zones.nix           layer 2: DNS on every zone          (CI, from master)
│  ├─ infra.nix            the `infra` app and the offline validate check
│  └─ registrar.nix        the `registrar` app: check and buy domains
└─ proton/
   ├─ vaults.nix           declared vaults and the `proton` app
   └─ secretspec.nix       generates ../../secretspec.toml
```

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
`parts/proton/secretspec.nix`) names every secret by vault and item title,
Proton Pass holds the value, and `proton plan` shows which references exist
and which are missing. Values never pass through git, and every vault opens
only through a Proton login carrying your 2FA.

A secret lives with the identity it belongs to, and the types enforce which
vault can be which:

| Vault | Holds | Must be |
| --- | --- | --- |
| `Zachariah-Root` | Cloudflare root token, bootstrap state, `registrar` token | a person's vault |
| `Kagamizo-LLC` | Kagamizo's own credentials: its GitHub organization, its logins | an LLC's or nonprofit's vault |
| `Kagamizo-CI` | `ci-apply` token, cloudflare state | CI only |
| `Kagamizo-Agents` | `agent-readonly` token, read-only state, OpenRouter key | agents only |

The registrar token is root-level although it is minted, not dashboard-made:
it spends money on the whole account and cannot be scoped to one LLC.

Every credential is a view. A Proton Pass agent token opens exactly one vault,
and secretspec turns a vault into the same environment variables every time,
so what a process can do depends only on which vault it was given.

| Role | Vault | Cloudflare token | Can |
| --- | --- | --- | --- |
| You (bootstrap) | `Zachariah-Root` | root | mint the tokens below |
| You (registrar) | `Zachariah-Root` | `registrar` | buy domains, within budget; read zones |
| CI on `master` | `Kagamizo-CI` | `ci-apply` | apply merged changes |
| Agents, PR plans | `Kagamizo-Agents` | `agent-readonly` | read everything, change nothing |

Vault names are declared once, in `parts/proton/vaults.nix`.

## Commands

```bash
nix run .#infra -- <bootstrap|cloudflare> <tofu args...>   # OpenTofu on a layer
nix run .#registrar -- check                               # price every candidate
nix run .#registrar -- register <domain> <price>           # buy one (billed, budgeted)
nix run .#registrar -- zone <domain>                       # its zone ID
nix run .#proton -- plan                                   # vaults and secret refs: the diff
nix run .#proton -- apply                                  # create declared vaults
```

`infra` and `registrar` need their secrets from secretspec, e.g.
`secretspec run --profile agent -- nix run .#infra -- cloudflare plan`.
In cloud sessions all four are on PATH (`.claude/hooks/session-start.sh`).

## Day to day, from the phone

1. Ask an agent for a change (a mailbox, a record, a token permission).
2. It edits the declarations and opens a PR.
3. The `infra` workflow posts a plan made with the read-only view. Read it in
   the GitHub app.
4. Merge. The `apply` job applies it with the `ci-apply` view.

Changes to `tokens.nix` only take effect when bootstrap is re-run; CI cannot
mint tokens.

**Kill switch:** `pass-cli agent delete <name>` cuts an agent token off
immediately. To kill Cloudflare access too, delete the token on the dashboard
(My Profile, API Tokens) or run bootstrap with `destroy`.

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

The `registrar` token is the only one that can buy domains, and it lives in
the root vault, so every purchase goes through this check and your Proton
Pass login (with 2FA). The ledger only knows what is declared, so record each
purchase right away; the command prints the lines to add.

## Adding a domain

1. Add names to the entity's `domainCandidates` and run `registrar check`.
2. Pick one. `registrar register <domain> <price>` buys it only if `<price>` is
   exactly the current registration cost and the month stays within budget, so
   nothing is charged by accident. Registrations are non-refundable.
3. Declare it under `identity.domains` with `registrar = "cloudflare"`, the
   `registration` lines the command printed, its mailboxes, and its `zoneId`
   from `registrar zone <domain>`. Re-run bootstrap so the ci and agent tokens
   cover the new zone.
4. In Proton: Settings, Domain names, add it. Copy the verification value and
   DKIM ID into the domain's `proton` field; the next apply publishes MX, SPF,
   DKIM and DMARC. Then create the mailboxes in Proton, one per declared name.

Proton has no API for domains or addresses, so step 4's Proton side is manual.

## Claude sessions

`.claude/settings.json` runs `.claude/hooks/session-start.sh` in cloud
sessions, which builds `.#session-tools` (pinned `pass-cli`, `secretspec` and
the three apps above) and puts it on PATH.

The session's network allowlist is declared, type-checked, in
`parts/claude/_environment.nix`. It cannot apply itself, so paste it once:
cloud environment menu, Edit, Network access **Custom**, tick *Also include
default list of common package managers*, and paste the output of
`nix build .#claude-allowed-domains && cat result` into Allowed domains.

## One-time setup

Done already: account and zone IDs, and the vaults (`proton apply`).

1. **Dashboard, once** (these need your login and 2FA):
   - **Root token:** My Profile, API Tokens, Create Token, template *Create
     Additional Tokens*. It is the only token that can mint others.
   - **Registrar:** a default payment method (Billing), a default registrant
     contact, and accepting the Domain Registration Agreement (Domains,
     Registrations). Needed only for buying domains.
2. **State bucket.** R2, create bucket `nix-images-tofu-state`. Then R2, Manage
   API tokens: one token *Object Read & Write* and one *Object Read only*, both
   scoped to that bucket. Each shows an S3 Access Key ID and Secret.
3. **Items.** Add these as Note items (title exactly as shown, value in the
   note body). `proton plan` lists whatever is still missing:

   | Item title | `Zachariah-Root` | `Kagamizo-CI` | `Kagamizo-Agents` |
   | --- | --- | --- | --- |
   | `cloudflare-token` | root token | after step 4 | after step 4 |
   | `cloudflare-registrar-token` | after step 4 | | |
   | `r2-state-key-id` | read & write | read & write | read only |
   | `r2-state-secret` | read & write | read & write | read only |
   | `tofu-state-passphrase` | passphrase A | passphrase B | passphrase B |
   | `openrouter-api-key` | | | your OpenRouter key |

   `Kagamizo-LLC/github-token` comes later, with the GitHub organization.

   Generate each passphrase with `openssl rand -base64 32`. A encrypts the
   bootstrap state (which contains token values), B the cloudflare state.

4. **Mint the tokens.**

   ```bash
   secretspec run --profile bootstrap -- nix run .#infra -- bootstrap apply
   secretspec run --profile bootstrap -- nix run .#infra -- bootstrap output -raw ci-apply \
     | secretspec set CLOUDFLARE_API_TOKEN --profile ci
   secretspec run --profile bootstrap -- nix run .#infra -- bootstrap output -raw agent-readonly \
     | secretspec set CLOUDFLARE_API_TOKEN --profile agent
   secretspec run --profile bootstrap -- nix run .#infra -- bootstrap output -raw registrar \
     | secretspec set CLOUDFLARE_API_TOKEN --profile registrar
   ```

   If the plan fails with *Unknown Cloudflare permission groups*, Cloudflare
   names one of them differently; fix the name in `tokens.nix`.

5. **Proton Pass agent tokens**, one per consumer, each limited to one vault:

   ```bash
   pass-cli agent create nix-images-ci   --vault Kagamizo-CI     --expiration 6m
   pass-cli agent create nix-images-plan --vault Kagamizo-Agents --expiration 6m
   pass-cli agent create orca-fleet      --vault Kagamizo-Agents --expiration 1m
   ```

   Each prints `PROTON_PASS_PERSONAL_ACCESS_TOKEN=pst_...`; keep the part after
   the `=`. `pass-cli agent monitor <name>` shows what each one read and why.

6. **GitHub.** Settings, Environments, new environment `cloudflare`, deployment
   branches limited to `master`, secret `PROTON_PASS_CI_TOKEN` (from
   `nix-images-ci`). Then a repository secret `PROTON_PASS_AGENT_TOKEN` (from
   `nix-images-plan`). Finally, the repository variable `INFRA_ENABLED` set to
   `true` switches the workflow on; until then both jobs are skipped.

7. **Existing records.** OpenTofu only manages what it created. Before declaring
   a record that already exists, import it (with the ci view, since import writes
   state), or delete it on the dashboard. Resource names are prefixed with the
   zone, e.g. `kagamizo-com-www`:

   ```bash
   secretspec run --profile ci -- nix run .#infra -- cloudflare import \
     'cloudflare_dns_record.kagamizo-com-www' '<zone id>/<record id>'
   ```

## The agent fleet (Orca)

[Orca](https://github.com/stablyai/orca) runs the agents on a computer and its
mobile app steers them. Give the fleet the agent view by signing in with the
`orca-fleet` token and starting Orca under secretspec, so every agent it
launches inherits `OPENROUTER_API_KEY` and the read-only `CLOUDFLARE_API_TOKEN`:

```bash
export PROTON_PASS_SESSION_DIR=$HOME/.pass-orca-fleet
pass-cli info >/dev/null 2>&1 || PROTON_PASS_PERSONAL_ACCESS_TOKEN=pst_... pass-cli login
secretspec run --profile agent --reason "orca fleet" -- orca
```

Agent sessions last two hours, after which `pass-cli login` has to run again.
Agents then change infrastructure the same way you do: by opening a PR.

## Not covered yet

- The registrar permission is declared as `Registrar Write`, after the docs'
  "Registrar write"; the first bootstrap confirms the exact name.
- Cloudflare Tunnel and Access (for God's Eye View on the Pi), Workers and
  Pages: the tokens already allow them; add the resources to `_zones.nix`.
