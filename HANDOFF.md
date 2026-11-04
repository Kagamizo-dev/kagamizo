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

Before anything else, check the network: `nix build .#session-tools` must reach cache.nixos.org. If the proxy refuses it (403), the session is not in the Kagamizo environment (see HANDOFF.md's "midday session"): stop and tell me, run nothing.

Sign the session in with `PROTON_PASS_KEY_PROVIDER=fs pass-cli login`; send me every link or code as a file card (SendUserFile, an HTML with the link) and a markdown link, never a bare URL; a Proton link lives nine minutes, a Cloudflare device code five, so send each the moment it exists and wait for my reply.

Then, in order, from HANDOFF.md's "Later on 2026-11-03: the always-on agents": confirm the agents tunnel is healthy (Cloudflare's API) and send me agents.jingzo.org and code.jingzo.org to open myself; move the host's iCloud exports from staging into Proton Drive; the typed machines.<name> contract; the trading plan (/root/.claude/plans/let-s-take-a-moment-imperative-milner.md, copied into HANDOFF.md); once Easy Switch has imported my mail, `mailbox senders` for the tally of every subscription, each to be declared with a card for me to mint.

The only thing you ask me for is approving a sign-in or 2FA link. Ask before anything else that spends money or applies infrastructure, unless HANDOFF.md says I already approved it. Every tool or API gets fully mapped from the pinned thing itself before it's used: Rust for what we write, Nix for packaging, Cedar for authorization, Lean for the proofs, all in the one modules tree; every module keeps its performance record (modules/perf). The allowlist is complete: never add a host to it; end the session with the updated start message, ready to paste. (The 'Public' email account profile update is still a pending action item on my end.)
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
| Brokerage | — (none needed) | public-jingzo, active; login on the outlook address; its API not relied on (terms) | public-mirazo, active; no login item in Pass, so governance refuses it; personal secret in the `Public` API-credential item, read |
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
- No client work (2026-10-31): no contracts, consulting or appointments,
  nothing that books the owner's time; income from algorithmic trading and
  published (market) research only. Kagamizo's consulting purpose is void;
  what Kagamizo becomes, and where trading is held (personal, or an entity
  with trader tax status), are open in the ownership discussion.
- Trading (2026-10-31): derivatives first (options), the lowest entry
  barrier; at least one decision a day, run algorithmically; a new strategy
  tried each week; Public or IBKR as the backend (both accounts exist);
  start with a small seed. Open: seed size, risk limits, cash or margin,
  options approval level, personal or company (see the ownership notes).
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
- Hetzner (2026-10-24): `modules/hetzner/host.nix` (jingzo-host: disko,
  no SSH server, follows the repository on a timer; a kexec installer that
  partitions and installs it) and `infra.nix` (`hetzner-infra plan|apply`:
  a fixed IPv4, a closed firewall and a cpx11 in fsn1, OpenTofu state
  encrypted in Jingzo-LLC-Sessions; it reads Hetzner's live prices and
  refused ash at $21.09; fsn1 plans at $6.59 against $7). Planned, not
  applied: the owner paused it to settle the NixOS pin and model hosting.
  The installer's initrd is ~555 MB on a 2 GB server: untested.
- nixpkgs is pinned directly to the newest stable branch, nixos-26.05
  (da6dc0e, 2026-10-21), the Pi flake following it; cdp.json and gh.json
  moved with it (Chromium 155).
- Model hosting (DeepSeek Flash-class, quantized, from Hugging Face) needs
  far more than the $7 host: tens of GB of RAM or a GPU. Pinning is ready
  to design (repo, commit, each file's SHA-256, like the Hetzner spec);
  serving by llama.cpp from nixpkgs. Waiting on the allowlist above and the
  owner's choice of machine and budget.
- Proton Pass: the owner wants tokens in its API-token custom items
  (hidden field), not notes. Done for reading (2026-10-31, below); the
  Cedar credential hierarchy is still to do.
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

## Where the 2026-10-31 session left it

- **Proton Pass items are typed.** `catalog/_json/pass-items.json` holds
  every item type's fields from the pinned pass-cli's own templates
  (stamped 2.4.2; `nix run .#pass-items-update` re-reads them, it needs the
  session) and the app's "API credential" template (API key, Secret: hidden;
  Expiry date: timestamp; Permissions: text), recorded from the owner's
  `Mirazo-Root / Public` item. A secret may live in one field of such an
  item (`secret { template; field; }`); the patched secretspec
  (`modules/proton/_patches/secretspec-protonpass.patch`) reads a note's
  body or a named field and refuses to write a field. Lean proves a field
  is only ever filled by the owner, and a token in a field is hidden.
- **Public's personal secret reads** from that item (`secretspec check
  --profile public`: found). `brokerage` is still refused by governance:
  public-mirazo has no Login item in Pass (the item titled `Public` is the
  API credential), and the login rule holds. Epic 5 makes the Login item
  (a flow onto finance@mirazo.org), then `brokerage summary` and the
  options level read.
- **Lean is the typing layer for every API** (`modules/lean`):
  `_lean/Api.lean` is one model (operations with typed inputs, typed
  values, `accepts` and its theorems: an accepted call names an operation,
  gives only its inputs, each of its type, and every required one). Every
  catalog in `catalog/_json` (14: CLIs, HTTP APIs, OpenTofu providers, CDP,
  REA, Proton Pass items) is rendered into it and checked
  (`checks.lean-api-<catalog>`); Mercury's API, CDP and the Pass items are
  proven closed (every named type declared), kernel-checked. A catalog
  bringing a type the model lacks fails the render. `_lean/Governance.lean`
  types all 251 governed actions: each Mercury and Public action's command
  is proven to be in the pinned CLI's catalog, and every agent grant proven
  free of spend, destroy and session (`checks.lean-governance`).
- Next for Lean: render every `cli.nix` call into a Lean `Call` and prove it
  `accepts` (today nix-effects checks them at evaluation); generate the Rust
  types (`mercury-cli` and `cards` as one program) from the same model; the
  Cedar base layer stated once, in Lean, with Cedar's policy checked
  against it.
- The disk filled once from VM-test closures (`nix flake check` fetches
  the desktop's); `nix-collect-garbage` freed 21 GB. The VM tests need
  KVM, which this container lacks.

## Where the 2026-11-01 session left it

§1–§3 of the approved plan are done, §4 begun; the rest is below.

- **CI was red on every push since 2026-10-27**, not from KVM: Hetzner
  edited its unversioned spec, so its fetchurl hash broke (cached locally).
  Fixed by stamping (`nix run .#hetzner-api-update`); CI then went green
  with both VM tests (tmux, desktop) on GitHub's KVM runners. This
  container has no KVM, so VM tests are CI's.
- **§1 Token accounts**: `accounts.held.<a>.credential = { item; template; }`;
  `pass-credential` confirms the item by field names and kinds;
  Cedar requires it (6169 tests); Lean proves the token is the owner's
  and hidden. public-mirazo's `Public` API credential is confirmed.
- **Public is blocked on one thing**: the Login item `Mirazo-Root /
  Public` now exists, but its address is admin@jingzo.org, while
  public-mirazo is declared on finance@mirazo.org. Either Public's sign-in
  moves to finance@mirazo.org (at Public, the owner's) and the item with
  it, or the declaration changes; the owner decides. No browser.
- **§2**: `api-check` (Rust, modules/lean/_src) decides from the Lean
  model's JSON whether a command line is the pinned CLI's; `brokerage`
  runs it first (an unknown command or option is refused before
  governance or Public). Lean proves the wrappers' calls accepted
  (`checks.public-calls`). Public has no backtest or paper API: backtests
  stay NautilusTrader on `historicdata bars`.
- **§3**: `modules/catalog/sources.nix` reads every catalog's version from
  its pin; `modules/catalog/README.md` is rendered from it and checked.
- **§4 begun**: `modules/ci` (typed workflows, GitHub renderer, Forgejo
  renderer checked but off, `checks.ci-rendered`, Lean `Pipeline.lean`:
  needs declared and acyclic, PR jobs never write). `checks` and the new
  weekly `spec-drift` are rendered. Still hand-written: build-image,
  infra, yoga-c940, github-bootstrap (they need typed releases, job
  outputs and environments). Still to do: the Rust runner
  (`nix run .#ci -- <job>`), the host's settings in OpenTofu.
- **§5 next**: `modules/site`, one site per domain generated from the
  declarations; `status.mirazo.org` behind Cloudflare Access (entities,
  domains, accounts with audit results, the Roadmap as a tracker, CI,
  catalog versions); landing and redirect pages; Chromium screenshots as
  CI artifacts. The first deploy is an apply: ask first.
- **§6 next**: the module contract (Lean, Rust, Kotlin twin, harness,
  Nix per module; a typed `modules.<m>` with Lean-checked dependencies;
  `checks.frozen`). The twin world: a Paper server pinned in Nix, local,
  offline mode, no account (the owner chose Minecraft, viewed through
  prismarine-viewer and bots); first module accounts & identity.
- Later: publishing targets (Ghost, PeerTube, a journal site with Zenodo
  DOIs, each declared as an account), a self-hosted tracker (Plane needs
  ≥4 GB), an audit typing every domain, alias and vault item.

### Later the same session (2026-11-01)

- **Payments typed**: every plan states its billing with a source; every
  account on a billed plan names exactly one payment: a Mercury card, the
  owner's card (which must name the Mercury card that replaces it: every
  payment ends on a Mercury card, the owner's rule), a waiver, or a Gap.
  Proton, Cloudflare and Northwest are paid personally today; their
  Mercury cards (proton, cloudflare, northwest-jingzo, hetzner) are
  declared on mercury-jingzo for the owner to mint (`cards plan` lists
  them). A card paying the owner's own account is booked as their draw.
  OpenRouter is now Jingzo's (dev@jingzo.org), not Kagamizo's.
- **Taxes** (`modules/money`): Mirazo an individual (no state income tax,
  the owner's statement; state not named), QSearch LLC disregarded into
  Mirazo's 1040; every Mercury category mapped to Schedule C or settled
  as personal/nondeductible/review; obligations per year with dates and
  sources (Wyoming's report waits on Jingzo's state and formation date).
  `nix run .#tax-report -- mirazo 2026 DIR` reads both Mercury accounts
  and writes the journal, Schedule C, review list and obligations; the
  six open 2026 transactions are decided (`money.decisions`, by id).
  Public's history is not read into it yet (named in the report).
- **Status page**: `modules/site`, generated from the declarations,
  screenshotted by `checks.site-status`; declared at status.mirazo.org
  (a Worker behind Cloudflare Access, only zach@mirazo.org). Planned with
  the read-only view: 4 to add. **Not applied**: this session's
  permission check refused `infra ci apply -auto-approve`; the owner
  approved the deploy, so the next step is that apply.

## Where the migration stands (2026-11-01, end of session; 2026-11-01 later)

The owner approved the migration plan (Apple, Google, both Outlooks and
Chase's checking into Proton and Mercury; GrapheneOS phones after).

- **Phase 0 done:**
  - `modules/migration`: sources, data classes, dependants; Lean proves
    nothing closes before it is emptied.
  - Every provider is declared from the owner's Pass items, and the
    `retiring` status is in place.
  - The new human steps are in the typed set: request-export,
    close-account and handle-device.
  - The tools are pinned: icloudpd 1.32.3, pyicloud 2026.10.1 (2307 tests
    pass), rclone, vdirsyncer and imapsync. icloudpd, rclone (its backends,
    every command and every global flag) and pyicloud (every service's
    methods and properties, asked of the library) are catalogued into
    Lean; `checks.catalog-coverage` holds the runner's calls to them.
  - Credit lines are typed.
  - `mailbox senders` and `icloud login|inventory` exist (governed).
- **Phase 1 (host and volume):** declared, priced and validated; not
  applied. The session's permission check refuses `apply -auto-approve`, the
  same as for status.mirazo.org. The owner allows both (a permission rule),
  or runs them:
  - `nix run .#hetzner-infra -- apply`
  - `nix run .#infra -- ci apply -input=false -auto-approve`
- **Phase 2 (inventory):**
  - `mailbox senders` needs Bridge's first full sync of the Proton
    mailbox. That is more than 100 minutes and over 1 GB here, so it runs
    on the host.
  - `icloud login` got no answer: `idmsa.apple.com` was not on the
    allowlist; it is now (declared). Next: `nix run .#icloud -- login`,
    relay the owner's code into /tmp/icloud-2fa-code, then
    `nix run .#icloud -- inventory <scratch>/icloud.json`.
  - The audit shows Chase has no login item in Pass. Public's login is
    admin@jingzo.org; the owner moves it to finance@mirazo.org.
- **Phase 3 (runners) written, not yet run:** `modules/migration/export.nix`
  and `_src` (Rust, `migrate`): `login icloudpd` and `login rclone` (each
  tool's own trusted session, the password piped from Proton Pass, Apple's
  code relayed through the FIFO, the session kept in Mirazo-Root-Sessions
  as ICLOUDPD_SESSION / RCLONE_ICLOUD_CONFIG); `photos`, `drive`, `notes`,
  `reminders` into a directory, each ending in `manifest.json` (every
  file's size and SHA-256; `rclone check` and the source's counts besides);
  `verify DIR` holds a copy to its manifest. Six governed actions on
  apple-mirazo. On the host, `modules/migration/_host.nix` (imported by
  the Hetzner host): the staging volume LUKS-formatted with a key kept in
  the host vault, and a nightly timer running every class then `verify`;
  idle until the host's Proton Pass token is delivered (a Gap).
- **Next:**
  1. The iCloud inventory (sizes, Hide My Email relays).
  2. Apply the host and volume, then run `mailbox senders` there.
  3. Run the Phase 3 sign-ins here (`migrate login icloudpd`, `migrate
     login rclone`: one code each), then `notes` and `reminders` here
     (small), `drive` and `photos` on the host once its token is delivered.
  4. Read the credit report for the card fates.

## Build times (2026-11-01, the owner's ask)

Every fresh container rebuilt the Rust crates, the Lean checks, the
catalogs, pyicloud's test suite and the host closure from source: the only
substituter was cache.nixos.org, the flake's own nixConfig is ignored here
(`accept-flake-config = false`), and nothing CI builds was kept anywhere.
Epic 4 is now declared (`modules/cache`): an R2 bucket served at
cache.kagamizo.com (public reads, no secret; OpenTofu in the Cloudflare
layer), a `cache` workflow pushing every check and package, signed, on
every push to any branch, under the new cache vault's agent token
(`nix-images-cache`, repository secret PROTON_PASS_CACHE_TOKEN), and the
session-start hook writing the substituter into the container's nix.conf.
To make it live, in order, each a session with Proton Pass signed in:

1. `nix run .#proton -- apply` (the cache vault and agent; the token into
   the root vault), then `nix run .#github-bootstrap` or CI's bootstrap
   for the repository secret.
2. `nix run .#bootstrap -- apply` with `cloudflare-login` (mints the
   `cache-push` token and derives its R2 S3 keys into the cache vault).
3. `nix run .#cache-key`: the signing key into the vault; declare the
   printed public key as `cache.publicKey` and in flake.nix's `nixConfig`
   (`extra-substituters`, `extra-trusted-public-keys`); `checks.cache-declared`
   holds the two together.
4. `nix run .#infra -- ci apply` (the bucket and its domain), then push:
   the `cache` workflow fills it; from then on sessions and runners pull.

Until then, prefer `nix build` of the one check a change touches over
`nix flake check` here, and leave the VM tests and the host closure to CI.

## Performance records (2026-11-01, the owner's rule)

Every module's measured targets live in `modules/perf` (`targets.nix`):
CI's `cache` workflow rebuilds each from scratch, times it, and
`perf-check` has Lean decide the fresh numbers against the committed
records (`_json/records.json`, `README.md` the report); a measurement
slower than the record by more than its tolerance fails the build, a
faster one moves the record (`perf-record` on the run's `perf.jsonl`
artifact, committed). Records are CI's runner's; this container's
baseline is in the report. First cut done: governance-cedar, 305 s to
under 1 s (`cedar-tests`, the tests in-process on the pinned crate).
lean-api-rclone's 37 s was container load: alone it is 7.7 s, 2.4 s of
it parsing the 197 KB model (no theorem is decided for rclone); the
records need CI's idle runner before the next cut is chosen.
migrate's release build (20 s) and catalog-coverage (3 s, Python over
every source) are next. Rust stays the implementation language
and Lean the proof; C only where a measured record demands it.

## The allowlist to apply (one change, all of it)

None. The owner's decision (2026-11-04): the allowlist is complete; no
host is added to it from now on. What runs on jingzo-host fetches through
the host's own network, never this session's proxy; the session checks
the host through the APIs already allowed (Cloudflare's tunnel status,
Hetzner's console), and the owner opens agents.jingzo.org and
code.jingzo.org themselves. A host the session cannot reach is worked
around, not added.

## Later on 2026-11-03: the always-on agents (read this first)

- **Cloudflare, applied** (state: 7 added): the remotely managed tunnel
  `jingzo-host-agents` (id 515fc4b0-c25c-4b27-9653-b268f0c08829), its
  ingress (agents.jingzo.org → localhost:8080, code.jingzo.org →
  localhost:4096, else 404), the Access policy for zach@mirazo.org, one
  Access application per name, and the proxied CNAMEs, each made after its
  application (`modules/cloudflare/_agents.nix`). The tunnel's token is in
  Kagamizo-Host/tunnel-token (`infra-tunnel-token`, never printed).
- **The host** (`modules/hetzner/{agents,_agents}.nix`): `agents-secrets`
  writes /run/agents from Kagamizo-Host (the capped chat-and-code OpenRouter
  key, the tunnel token); `open-webui` (trusts Access's
  Cf-Access-Authenticated-User-Email; the one unfree package admitted);
  `opencode-web` with the repo's OpenCode config; `cloudflared-agents`.
  Pushed as b46cadb; the host switches at its 04:40 UTC autoUpgrade
  (2026-11-04), building Open WebUI itself (not in cache.nixos.org; this
  session's proxy blocks its GitHub tarball).
- **To check after 04:40 UTC:** the tunnel's status from Cloudflare's API
  (agent profile; `inactive` before the switch, `healthy` after), then
  `host-console` for the units; then send the owner both links to open
  themselves (the session cannot reach them, by design). If the switch failed, `host-console` shows
  the failed units; reinstalling (dated window, `hetzner-infra reinstall`,
  `host-install`) is the fallback.
- **The homepage** (2026-11-04, applied): status.mirazo.org is now the
  one home for everything, generated by `modules/site` from the
  declarations: app tiles (agents, code), infrastructure cards (the host,
  Cloudflare, Proton, the stack), Mercury cards, OpenRouter keys, the
  owner's steps, then the records (entities, domains, accounts, Gaps, tax,
  credit lines, migration, CI, catalogs), with a sidebar. Sign-in is one
  Access session for all three names: a one-time code mailed to
  zach@mirazo.org, now declared (`cloudflare_zero_trust_access_identity_provider.otp`).
  Next on it: live tiles (tunnel health, host up, OpenRouter spend, card
  balances) from a Worker holding read-only tokens as secret bindings.
- **Money between entities, to design next:** seeding from Mirazo's
  personal Mercury (mercury-mirazo) to Jingzo's (mercury-jingzo) as a
  typed, dated flow (`as = contribution`, like `mercury.cards.*.between`),
  executed by Mercury's `payments transfer` (a spend: the owner approves
  each). Open for the owner: whether the trading account is personal
  (public-mirazo today) or the LLC's, which decides where the $100 seed
  lands.

## Where the 2026-11-03 session left it

- **jingzo-host is up** (2026-11-03, 05:10 UTC): NixOS from the repository,
  installed by nixos-anywhere from the `host-install` workflow (no SSH on
  the installed host; the firewall admits nothing; `hetzner-infra plan`: no
  changes). It signed in with its delivered Proton Pass token and keeps its
  staging volume's LUKS key in Kagamizo-Host-State; the 250 GB volume is
  LUKS, mounted.
  - Credentials: `hetzner.host.credentials` (typed, scoped, dated):
    Apple login (read-only, Kagamizo-Host), iCloud session (writable,
    Kagamizo-Host-State), the host's token (Kagamizo-Install, written to
    /var/lib/kagamizo/host-token at install), Hetzner's token for the
    console (until 2026-11-17). `host-credentials sync` copies and expires.
  - Lessons, each now in code: pass-cli refuses an agent's commands
    without PROTON_PASS_AGENT_REASON; a second login is refused ("Already
    authenticated"), so sign in once a boot and clear the session at boot;
    an agent is read-only in its own vault, so the host writes
    Kagamizo-Host-State; the hcloud provider never clears a firewall's
    last rule (a TEST-NET-1 rule closes it); a workflow is dispatchable by
    hand only once on main (request files start them here).
  - Seeing the host: `host-console` (screenshot plus tesseract text),
    `host-rescue <ip> [read|reset-session]` (Hetzner rescue: mounts the
    disk, prints the journal through NixOS's journalctl). Both need the
    window open for rescue; the console needs none.
- **Next on the host:** the nightly export (02:10 UTC) runs notes and
  reminders from the delegated pyicloud session. Photos and Drive need
  icloudpd's and rclone's own sessions: `migrate login icloudpd` and
  `migrate login rclone` here (one Apple code each), then delegate both
  sessions to Kagamizo-Host-State. Then a typed `machines.<name>`
  contract for every server, container and device (hardware, disk,
  install, network, credentials, observability, services), checked by
  Lean before anything is built.
- **iCloud:** signed in (the code fixes: the code is now requested, and an
  SMS code is checked with the mode it was sent with). Inventory: 116 GB
  used (photos 79 GB, device backups 35 GB, docs 1.8 GB, mail 0), 3333
  photos, 446 contacts, 6 calendars, 708 notes, 4 Hide My Email relays
  (junk, dropped). The JSON stays out of the repository.
- **Mercury:** mercury-jingzo signed in. `cards plan` now discovers every
  live card: Research-OpenRouter (••5055, $50/week) and Media (Netflix,
  ••1975) are declared. `cards vault` stores agentic cards into Proton
  Pass; neither card is agentic.
- **Proton Pass items:** owner-issued secrets live in typed items, never
  notes (Lean: by_hand_in_field). Prepared for the owner to fill:
  Jingzo-LLC/openrouter (signup), Jingzo-LLC/openrouter-management-key
  (paste into Secret), Mirazo-Root/icloud-app-password, Mirazo-Root/Chase.
- **Waiting on the owner:** the OpenRouter signup and key; Easy Switch
  imports of Gmail and both Outlooks (for the tally of subscriptions);
  minting the remaining cards after the tally.
- **Also new:** modules/tokens (the credential graph, Lean-decided),
  modules/statestore (OpenTofu state in Proton Pass, Lean-proven writes).

## Where the 2026-11-01 evening session ended (read this first)

Supersedes the evening notes below where they disagree.

- **R2 is on** (the owner, in the dashboard: Cloudflare sells it only
  there, API code 10042). Typed: `operations.humanSteps.enable-product`,
  `accounts.products.cloudflare` (r2, zeroTrust), and
  `accounts.held.cloudflare.products.r2`; the cache demands it, so `infra`
  and `bootstrap` fail evaluation, naming the step, without it; Lean
  proves every turned-on product came from that step.
- **The cache bucket is live**: `kagamizo-nix-cache` at cache.kagamizo.com
  (`infra ci apply`). Empty until the `cache` workflow runs, which needs
  PROTON_PASS_CACHE_TOKEN (below). The `cache-push` token and its R2 S3
  keys are minted into Kagamizo-Cache (`bootstrap apply`; the cf sign-in
  needs "API Tokens: create" ticked on Cloudflare's consent page).
- **The Cloudflare state was lost and rebuilt.** The first apply's save
  failed and secretspec had already deleted the old item (delete, then
  create). Fixed twice over: the secretspec patch now creates first, and
  OpenTofu states no longer live in a secretspec note at all (next point).
  The 25 DNS records were adopted unchanged through typed import blocks
  (`cloudflare.imports`, ./modules/cloudflare/imports.nix).
- **`modules/statestore`: Proton Pass as an OpenTofu backend.** Typed
  backends (`statestore.backends.<layer>`: declared vault, item prefix,
  chunk size), generations of chunked notes plus a hashed manifest, the
  old generation deleted only after the new one reads back.
  `_lean/Store.lean` proves the write never loses a state after any
  prefix, completes, and chunks losslessly within the limit; lock is an
  item created only when absent. Rust (`_src`) serves OpenTofu's `http`
  backend on the loopback; `statestore-run <layer> [--read-only] -- cmd`
  wraps a run. `infra` (Kagamizo-State, `cloudflare@<g>`) and
  `hetzner-infra` (Jingzo-LLC-Sessions, `hetzner@<g>`) use it; both moved
  byte-identical and plan no changes. The old notes `tofu-state` and
  `hetzner-tofu-state` are kept, stale, as a fallback; delete them once a
  later apply has run on the new backend.
- **status.mirazo.org waits for Zero Trust**: the whole layer (Worker,
  domain, Access) is included only once
  `accounts.held.cloudflare.products.zeroTrust` is declared, so the page
  is never served without Access. The Worker made by the first apply still
  exists at Cloudflare, unserved (no workers.dev subdomain, no route).
  Turning on Zero Trust is the owner's dashboard step, like R2.
- **The cache is filled.** PROTON_PASS_CACHE_TOKEN is set (github-bootstrap,
  19:16). The `cache` workflow then failed twice and was fixed: the pinned
  protonpass/install-cli-action shipped no dist/index.js (workflows now
  install the flake's own pass-cli, version-checked), and one failed
  download from cache.nixos.org sank a whole build (cache-push now runs
  `--keep-going --fallback` and pushes whatever built). Run 41343110404
  pushed in 40 min; the bucket holds over 1000 narinfos. Sessions pull
  once cache.kagamizo.com is on the allowlist (above); then measure the
  bootstrap and every workflow against modules/perf before deciding on
  a self-hosted build box (the owner asked; it would be a priced Hetzner
  server as Nix remote builder and runner, locked to trusted branches,
  since the repository is public).
- **jingzo-host never ran its first boot** (unchanged; see below).
- **The owner's architecture direction (2026-11-01)**: every module typed
  end to end: Proton Pass typed inside the infra layer (statestore is the
  first piece), Lean proofs and research papers as required, typed
  sources per module, and each module with its own typed Nix build and
  deployment environment. Next: the module contract of §6 carrying
  `sources` (papers, specs, each typed with what it supports) and
  `environments` (build, deploy), checked by Lean.

## Where the 2026-11-01 evening session left it

- The network was right (cache.nixos.org, Cloudflare, Hetzner, Apple all
  answered), and Proton Pass signed in (automations@kagamizo.com).
- **The Cloudflare apply ran, partly.** The plan was re-made (the saved one
  died with its container): 6 to add, as recorded. Applied with the owner's
  approval: only `cloudflare_workers_script.status` (kagamizo-status) was
  created. R2 refused the bucket (not enabled on the account, code 10042)
  and Access refused the policy (not enabled); see the Gaps. The state save
  then failed (no `tofu-state` item had ever existed; creating it gave
  InvalidValue, probably a note size limit), so the Worker exists outside
  the state. It is not exposed: the account has no workers.dev subdomain and
  the script's own is disabled. The next apply re-creates it with a PUT,
  which overwrites it in place.
- **Blocked until the owner decides**: how the state is stored (a Pass
  attachment, a smaller state, or R2 once it exists), and whether to declare
  R2's subscription and the Zero Trust organization (`cloudflare_account_
  subscription`, `cloudflare_zero_trust_organization`, with the token
  groups to read and write them). So the `cache-push` token and
  PROTON_PASS_CACHE_TOKEN were not attempted: there is no bucket to push to.
- **jingzo-host's first boot did not run.** Hetzner: running since
  12:58:34Z, cx23, image ubuntu-24.04, one volume; actions only
  create_server and start_server. Metrics since creation: CPU at most 1%,
  inbound network at most 19 B/s, almost no disk writes. Installing Nix
  and the installer would have pulled hundreds of MB, so the script failed
  at once or never started. With no SSH, its log
  (/var/log/kagamizo-first-boot.log) is out of reach; Hetzner's console
  (`request_console`, VNC) or a rebuild are the ways in, both the owner's
  call. Meanwhile it bills (cx23, IPv4 and the 250 GB volume).
- **R2, approved (2026-11-01 evening):** the owner approved a one-shot
  billing token: declared, minted with a root credential, used once to
  enable R2's subscription (`cf accounts subscriptions create
  --rate-plan-id ... --dry-run` first), then deleted. The standing ban on
  Billing in tokens stays. Not built yet, for two reasons:
  - R2's rate-plan id is not published where this session could read it
    (Cloudflare's tenant reference lists zone plans only) and no pinned
    thing names it; it is not to be guessed. developers.cloudflare.com is
    not on the allowlist (below); dash.cloudflare.com is, but answers
    non-browser clients with Cloudflare's own 403.
  - `cf`'s sign-in can never hold billing scopes (cf drops billing:read
    and billing:write before validating; the catalog now knows it), and
    Cloudflare granted it every requested scope **except
    `account_api_tokens:create`** (`cf auth whoami`: 36 scopes). So
    `bootstrap` cannot mint any token from the cf session: `bootstrap
    plan` fails listing permission groups (403, code 9109). That, not a
    pending device grant, is why the cache-push token never came. Minting
    needs another root credential, e.g. a user API token with "API
    Tokens Write" kept in Mirazo-Root-Sessions; it would also mint the
    one-shot billing token.
- Not started: `icloud login`, the Phase 3 sign-ins, `mailbox senders`.

## Where the 2026-11-01 midday session left it

- **Nothing ran: the session was not in the Kagamizo environment.** Its
  container (a `remote_cowork` workspace, not the cloud environment with
  the custom network) reached github.com and nothing else: the proxy
  answered 403 to `cache.nixos.org`, the GNU mirrors, PyPI, npm,
  crates.io, `api.cloudflare.com`, `proton.me`, `api.hetzner.cloud`,
  `idmsa.apple.com` and the Apple websocket hosts alike. Since the package
  managers' defaults were refused too, this is not a missing host: the
  declared allowlist was not the one in force. `nix build .#session-tools`
  fails at its first fetch, so there is no pass-cli and no sign-in.
- The repository was cloned by hand, so the session-start hook never ran
  either (no session tools, no commit-msg hook).
- Everything under "Where the 2026-11-01 afternoon session left it" is
  still the next work, in the same order.

## Where the 2026-11-01 afternoon session left it

- **Proton Pass signs in** once the link reaches the owner: the app drops
  a bare URL from a message, so links go as a file card (SendUserFile,
  an HTML with the link) plus a markdown link; a link lives nine minutes
  (the CLI's own poll window), a Cloudflare device code five.
- **The Hetzner host is live**: jingzo-host, cx23 in fsn1, 2.31.96.54,
  with the 250 GB staging volume; its first boot installs commit 926da28.
  cpx11 is withdrawn from the EU (the plan now refuses withdrawn types,
  read live); `hetzner-prices` keeps the price ledger
  (`modules/hetzner/_json/prices.json`), the owner's ask. Budget $27.
- **The cache**: the vault and agent exist (`proton apply`), the signing
  key is in the vault and its public half declared (flake.nix nixConfig,
  `cache.publicKey`). Not done: the bucket and status.mirazo.org apply
  (this session's permission check refused the apply as a DNS change; the
  plan, saved to a file, is 6 to add), the `cache-push` token (the
  Cloudflare root sign-in's device grant stayed "authorization pending"
  through five codes the owner approved; `bootstrap derive-r2`, deriving
  the R2 keys from ci-apply instead, was refused as credential
  exploration), the repository secret PROTON_PASS_CACHE_TOKEN (github
  bootstrap). The owner allows those with a permission rule, or runs them.
- **iCloud**: `icloud login` reaches Apple and gets the 2FA challenge, then
  the pinned pyicloud opens a websocket to websocket.push.apple.com
  directly for the trusted-device prompt; the host is not allowed (above)
  and the dial bypasses the proxy; `_icloud.py` now dials it through the
  proxy once the host is allowed.
- **Performance**: `modules/perf` (records per module, Lean-decided,
  measured by CI's cache workflow); the Cedar check 305 s to 1 s.

## Roadmap

ETAs are working time for a session once nothing blocks it; "you" is the
owner's part, always an approval. Order is the order of work.

| # | Epic | Stories | Blocked on | You | ETA |
|---|---|---|---|---|---|
| 0 | **Validate before acting** | Host map per provider from a submitted sign-in (explore runs); a Cedar test for every flow (allowed for the controller under its effect, denied to agents); every tool and API checked against its pinned catalog, with a coverage report per module | the allowlist above | — | 3 h |
| 1 | **Mercury, Jingzo's own login** | Explore the signed-in pages; invite finance@jingzo.org (team settings); its passkey (after an authenticator-app 2FA); login item in Jingzo-LLC; `login.passkey.rpId`; `mercury-session --account mercury-jingzo login` | the allowlist | sign-in approval; Mercury link; the invite mail until epic 3 | 2 h |
| 2 | **$5 OpenRouter card** | `mercury.account = "mercury-jingzo"`, `cards plan`, `cards apply` | 1; how to record it between Jingzo and Kagamizo (owed, or wait) | that decision | 30 min |
| 3 | **Confirmation mail** | Bridge headless under Nix, its login driven from Proton Pass; a Rust IMAP reader (declared addresses, declared senders, links on the flow's hosts only); then the outlook mailbox the same way | — | one Proton sign-in approval | 6 h |
| 4 | **Build cache and CI** (approved) | Declared (`modules/cache`, above): the four steps to make it live; then `nix flake check` one job per check; Rust with crane | Proton Pass signed in | — (a Gap if R2 is not enabled) | 2 h |
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

## The approved trading plan (2026-11-02)

### Options trading on Public: research agents → backtest → paper → gated live

#### Context

The owner wants to drop unclear paths (Apple is parked; an emailed
data-copy request to Apple comes later) and build only on direct APIs:
NautilusTrader, Public, Mercury and OpenRouter. The target is one
pipeline:

1. **Research:** LLM agent loops run in parallel on OpenRouter, using
   TradingAgents (TauricResearch/TradingAgents).
2. **Backtest:** TradingAgents' own `run_backtest`, plus NautilusTrader for
   the options execution.
3. **Paper:** real chains and Public's preflight; no order is placed.
4. **Live:** gated. The owner approves every order.

What exists:
- **NautilusTrader 1.231.0** (`modules/trading`): backtest and paper
  preflight of one equity example. The adapter `_public.py` is stdlib REST
  with EQUITY hard-coded.
- **Public CLI 1.3.7** (catalog `public.json`): option chains, greeks,
  preflight single and multi, place and place-multileg (spend), cancel
  (write), order status, portfolio.
- **Orca fleet** (`modules/governance/orca.nix`, `modules/openrouter/
  opencode.nix`): declarations only. `orca` and `opencode` are not
  packaged. Not needed for this plan; it comes later as the steering UI.
- **OpenRouter** (`modules/openrouter`): status `planned`; the wrapper
  `openrouter plan|apply` mints capped keys from a management key. Payment
  is declared as Mercury card `openrouter` ($5), which was never issued.
- **TradingAgents** (Apache-2.0, v0.7.1, arXiv 2412.20138):
  - Analysts, a bull/bear debate, a trader, risk and a portfolio manager.
  - Any OpenAI-compatible endpoint, OpenRouter included (`backend_url`,
    `deep_think_llm` and `quick_think_llm`).
  - Its own `run_backtest` scores alpha over a ticker and date grid.
  - Equities only. Its decisions go to a simulated exchange, never to a
    broker.

The owner's decisions (2026-11-02):
- **Public's login:** keep admin@jingzo.org for now, as a typed, dated
  exception.
- **Limits:** $100 seed, defined-risk options only, $25 max premium per
  trade, 1 open position, stop for the day after a $25 loss.
- **Approval:** the owner approves every live order.
- **OpenRouter:** paid by the Mercury card. Research budget $20/month.

#### Owner's steps (typed human steps; all one-time)
1. **mint-card:** in Mercury's app, the card `kagamizo/openrouter` on
   Jingzo's account, $20/month, locked to OpenRouter. Only the owner mints
   or cancels cards; agents never can. Card discovery (G) then finds it and
   checks it against the declaration.
2. **sign-up**, then **console-credential:** I send the OpenRouter sign-in
   link as a file card plus a markdown link. The owner signs in as
   dev@jingzo.org (passkey), makes the first management key and the first
   top-up from the card. The owner pastes the key into the Proton Pass item
   I created beforehand: `Jingzo-LLC / openrouter-management-key`, an "API
   credential" item with every field but the secret filled in (F). That
   paste is the only manual storing.
3. **approve-payment:** deposit $100 into Public, and confirm options are
   enabled on the account.

#### F. Proton Pass items, typed; no secret as a note
- **Rule:** a secret's store is a typed item made from a template (API
  credential, login, password, SSH key), never a note.
  - `modules/_lib/secret.nix`: `store = { template; item; field; }` is
    required for every secret a human issues. Evaluation fails on a note.
  - `modules/operations/_lean/Boundary.lean`: a theorem that a secret
    issued by a human step is stored in a hidden field of a template item.
- **`pass-prepare <secret>`:**
  - Creates the declared item with `pass-cli item create custom
    --from-template` (the template's JSON shape is read from pass-cli's own
    `--get-template` and recorded in `catalog/_json/pass-items.json`).
  - Fills everything declared: title, vault, and the non-secret fields
    (Permissions, Expiry date, the provider's URL in a note field of the
    template). The secret field is left empty.
  - It then reads the item back and confirms its shape, using
    `pass-credential`.
- **After the owner's paste:** `secretspec check` sees the field filled.
  The value is never read into the terminal; it is only piped to the tool
  that uses it.
- **OpenRouter's management key** moves from a note store to the API
  credential's `API key` field. Every other human-issued secret today
  (`hcloud-token`, `public-personal-secret` already done) follows the same
  pattern.
- **Values automation writes** (OpenTofu state chunks, sign-in sessions,
  minted keys) are still notes today. These move to a typed custom item too
  ("kagamizo-blob": a hidden `value` field plus `kind`, `written` and
  `sha256`). That needs field writes, in statestore and the secretspec
  patch, which today refuses to write fields. This is staged after the
  trading path, and recorded as a Gap until then.

#### G. Card discovery, typed (`modules/mercury/cards.nix`)
- **`cards discover`:** a read through `mercury-cli cards list`, an
  observed read. It writes `modules/mercury/_json/cards.json`, one entry
  per live card: id, nickname, status, account, spending limit and period,
  and merchant lock. The fields are typed from the pinned Mercury SDK's
  card schema (`catalog/_json/mercury-api.json`); no card number, CVC or
  expiry is written.
- **Typed check** (`checks.cards-declared`):
  - every declared `mercury.cards.<v>` is live, active, on its declared
    account, with its declared limit
  - every live `kagamizo/*` card is declared
  - a mismatch fails, naming the card and the field
  - a Lean fact list proves the same match for the committed discovery
- **Governance:** `cards apply` stays refused, and minting stays the
  owner's (`mint-card`). The `cards create` and `cards update` effects
  stay spend and write, controller only. Agents never get them.

#### Plan

#### A. Unblock Public (typed, dated exception)
- `modules/accounts/options.nix`: add `held.<a>.login.exception = { email;
  until; because; decided }`. `loginProblems` accepts the off-domain address
  only while the exception names it.
- `modules/governance/cedar.nix`:
  - Add the exception's address and its expiry (a YYYYMMDD integer) to the
    account entity.
  - `governance-authorize` passes `context.today`.
  - `logins-say-whose-they-are` admits `login == exception.email && today
    <= until`.
  - New Cedar tests: admitted before expiry, refused after, refused for any
    other address.
- `modules/public/account.nix`: public-mirazo's exception is
  admin@jingzo.org until 2026-11-30.
- `modules/lean/_lean/Governance.lean`: a theorem that an exception never
  covers another address or a later date.

#### B. OpenRouter for the research loops
- `modules/openrouter/card.nix`: `limitUsd = 20` (the owner's budget).
- `modules/openrouter/openrouter.nix`: one key, `research`, at $20/month,
  in a new secretspec profile `research`.
  - The existing keys (chat-and-code, orca-fleet and swarms-*) stay
    declared but are disabled until their own budget is approved.
  - New typed check: the sum of the enabled caps is at most the paying
    card's limit, otherwise evaluation fails.
- After the owner's steps: `openrouter apply` mints `research`, and
  `openrouter credits` confirms the balance.
- `modules/tokens`: the research key joins the credential graph. Its root
  is the management key, a console-credential root.

#### C. TradingAgents, packaged and governed (`modules/research`)
- A flake input pinned at the v0.7.1 commit, built with
  `buildPythonPackage`. Python deps come from nixpkgs where present, and
  are otherwise pinned by hash.
- Map it from the pinned source before use, into
  `catalog/_json/tradingagents.json`:
  - its config keys
  - its data sources, each with its host: Yahoo Finance, SEC EDGAR, FRED,
    Alpha Vantage, StockTwits, Reddit, Polymarket
  - which sources need keys
  The hosts go into `modules/claude/_environment.nix` (a new `research`
  group), and the next allowlist carries them.
- `research run TICKER DATE` writes one decision with the full debate
  transcript to `research/<date>/<ticker>.json`.
  - Config is generated by Nix: `llm_provider = openai_compatible`, the
    OpenRouter `backend_url`, deep and quick models from the declared
    open-weight list, `max_debate_rounds`.
  - The key comes from secretspec profile `research`.
  - It runs under `frozen.nix`: `env -i`, declared variables only.
- `research sweep TICKERS FROM TO --jobs N` runs one isolated process per
  ticker-date, in parallel, all on the shared $20-capped key.
- `research backtest …` wraps TradingAgents' `run_backtest` over the same
  grid and records alpha against the benchmark.
- Governance: research reads only market data. It calls no broker and
  needs no account action, so it needs no Cedar grant.

#### D. From decision to defined-risk option (`modules/trading`)
- `trading.limits.public = { seedUsd = 100; maxPremiumUsd = 25;
  maxOpenPositions = 1; dailyLossStopUsd = 25; allowed = [ "long-call"
  "long-put" "debit-spread" ]; }`.
- `_lean/Risk.lean`:
  - `admissible`: an allowed kind, max loss within the cap, open positions
    below the max, the day's loss below the stop.
  - Theorems: an admissible order's max loss is at most `maxPremium`, and a
    day loses at most `stop + maxPremium`.
  - `checks.trading-risk` decides the declared limits.
- `_public.py`, every endpoint mapped from the pinned CLI's generated
  client:
  - option expirations and chain, greeks
  - an OPTION order body (OSI symbol, open/close, LIMIT, DAY)
  - preflight single and multi
  - place and order status, called only by `trade place`
  The offline stub `_stub_public.py` gains a chain and a preflight.
- Strategy kind `agent-option`:
  - Takes the day's TradingAgents decision (BUY, SELL or HOLD) for the
    underlying: BUY becomes a call, SELL a put, HOLD means no trade.
  - Contract: the nearest expiration 7 to 21 days out, the cheapest strike
    with ask × 100 ≤ $25 and |delta| ≥ 0.15. If none fits, no trade.
  - Declared as `trading.strategies.spy-agents` on SPY.

#### E. Stages and gates (typed, Lean-checked)
- `trading.strategies.<s>.stage` is `research`, `backtest`, `paper` or
  `live`. Promotion is declared with evidence:
  - **backtest → paper:** a recorded backtest (grid, alpha, max drawdown)
    meeting declared thresholds.
  - **paper → live:** N recorded paper days with preflight-accepted
    proposals, plus the owner's dated decision.
  - `_lean/Stages.lean` proves no strategy is `live` without both pieces of
    evidence. `trade place` refuses unless the stage is `live`.
- Commands:
  - `trade propose <s>`: the day's research decision, the risk check and
    Public's preflight. Writes `proposal.json` and sends the owner a
    summary.
  - `trade place proposal.json`: the governed spend action, controller
    only. It re-runs the risk check and the preflight, places, then polls
    order status.
  - `trade paper-day <s>`: propose without placing; the day is recorded as
    paper evidence.

#### Order of work
1. A and the read-only Public checks (brokerage summary, option chain).
   These need nothing from the owner.
2. F's rule and `pass-prepare`, then create the OpenRouter item. G's
   `cards discover`.
3. C's packaging and catalog, D's limits and Lean, and E, all built and
   checked offline.
4. The owner's step 1, then `cards discover` confirms the card. The owner's
   step 2 (my link, their sign-in, their paste). Then B: `openrouter
   apply`, and the first research run.
5. Research sweep and backtest, then paper days on SPY.
6. The owner's step 3, then the promotion decision, then `trade propose`
   and the owner's approval of `trade place`.

Timing: A and the read-only Public checks are realistic for tomorrow
morning. Live placement needs the paper evidence and the owner's
promotion, so it is not tomorrow.

#### Files
- `modules/accounts/options.nix`, `modules/governance/cedar.nix`,
  `modules/lean/_lean/Governance.lean`, `modules/public/account.nix`
- `modules/openrouter/{card,openrouter,secrets}.nix`, `modules/tokens/
  default.nix`
- New `modules/research/` (`default.nix`, `_src` or `_py`, `_lean`), a
  flake input, `catalog/_json/tradingagents.json`
- `modules/trading/{strategies.nix,_trade.py,_public.py,_stub_public.py}`,
  and new `_lean/Risk.lean` and `_lean/Stages.lean`
- `modules/public/_lean/Calls.lean`: add the option commands
- `modules/perf/targets.nix`, `modules/claude/_environment.nix`
  (research hosts), HANDOFF.md, the Gaps (Public funding has no API; card
  minting is the owner's)

#### Verification
- Checks: trading-backtest (with the options stub), trading-risk,
  trading-stages, research-catalog, a research smoke run against a stubbed
  OpenAI-compatible endpoint, public-calls, governance-cedar,
  lean-governance, tokens-graph, operations-boundary, formatting, statix
  and deadnix.
- Live, read-only: `brokerage summary` and `brokerage market option-chain
  SPY <date>` through the exception.
- After OpenRouter exists: `research run SPY <date>`, then a small
  `research sweep`, with `openrouter credits` checked against the cap.
- Paper: `trade paper-day spy-agents` gives a preflight-accepted proposal
  within $25.
