# infra: Cloudflare as code

Everything on the Cloudflare account is declared in Nix, rendered to OpenTofu
JSON, and changed only through a reviewed plan. Secrets are never in this
(public) repo: `secretspec.toml` names them, Proton Pass holds them.

## The model

Every credential is a view. A Proton Pass vault holds one view; a Proton Pass
agent token opens exactly one vault; secretspec turns the vault into the same
environment variables every time.

| Role | Proton Pass vault | Cloudflare token | Can |
| --- | --- | --- | --- |
| You (bootstrap) | `nix-images-root` | root (creates tokens) | mint and rotate the tokens below |
| CI on `master` | `nix-images-ci` | `ci-apply` | apply merged changes |
| Agents, PR plans | `nix-images-agents` | `agent-readonly` | read everything, change nothing |

The two Cloudflare tokens are themselves declared in [`tokens.nix`](tokens.nix),
so changing what an agent may do is a reviewed diff too.

```
infra/
├─ settings.nix    account/zone IDs, state bucket, token expiry, DNS records
├─ tokens.nix      the token profiles (views)
├─ bootstrap.nix   layer 1: mints tokens.nix          (you, by hand)
├─ cloudflare.nix  layer 2: DNS and everything else   (CI, from master)
└─ default.nix     renders the layers, the `infra` app, the validate check
```

`nix run .#infra -- <bootstrap|cloudflare> <tofu args...>` runs OpenTofu (with
the Cloudflare provider pinned by `flake.lock`) on a layer. State is in R2,
encrypted client-side with `TOFU_STATE_PASSPHRASE`. `nix flake check` validates
both layers offline against the provider schema.

## Day to day, from the phone

1. Ask an agent for a change (a record, a subdomain, a token permission).
2. It edits `settings.nix` / `cloudflare.nix` / `tokens.nix` and opens a PR.
3. The `infra` workflow posts a plan made with the read-only view. Read it in
   the GitHub app.
4. Merge. The `apply` job applies it with the `ci-apply` view.

Changes to `tokens.nix` only take effect when you re-run bootstrap (step 5
below); CI cannot mint tokens.

**Kill switch:** `pass-cli agent delete <name>` cuts an agent token off
immediately. To kill Cloudflare access too, delete the token on the dashboard
(My Profile, API Tokens) or run bootstrap with `destroy`.

## Claude sessions

`.claude/settings.json` runs `.claude/hooks/session-start.sh` in cloud
sessions, which builds `.#session-tools` (pinned `pass-cli`, `secretspec` and
the `infra` app) and puts it on PATH.

The session's network allowlist is declared, type-checked, in
`claude/environment.nix`. It cannot apply itself, so paste it once: cloud
environment menu, Edit, Network access **Custom**, tick *Also include default
list of common package managers*, and paste the output of
`nix build .#claude-allowed-domains && cat result` into Allowed domains.

## One-time setup

Do these in order. Steps 4 to 6 need `pass-cli` signed in as you (the Yoga live
USB has it) plus `secretspec` 0.21+ and `pass-cli` 2.1+ (agent tokens).

1. **Settings.** Fill in `accountId`, `zoneId` and `zone` in `settings.nix`.

2. **State bucket.** On the dashboard: R2, create bucket
   `nix-images-tofu-state`. Then R2, Manage API tokens, and create two tokens
   scoped to that bucket: one *Object Read & Write*, one *Object Read only*.
   Each shows an S3 Access Key ID and Secret Access Key.

3. **Root token.** My Profile, API Tokens, Create Token, template
   *Create Additional Tokens*. This is the only token that can mint others;
   it stays in your own vault.

4. **Vaults and items.** Create three vaults and add these as Note items
   (title exactly as shown, value in the note body):

   | Item title | `nix-images-root` | `nix-images-ci` | `nix-images-agents` |
   | --- | --- | --- | --- |
   | `cloudflare-token` | root token (step 3) | after step 5 | after step 5 |
   | `r2-state-key-id` | read & write | read & write | read only |
   | `r2-state-secret` | read & write | read & write | read only |
   | `tofu-state-passphrase` | passphrase A | passphrase B | passphrase B |
   | `openrouter-api-key` | | | your OpenRouter key |

   Generate each passphrase with `openssl rand -base64 32`. A encrypts the
   bootstrap state (which contains token values), B the cloudflare state.

5. **Mint the tokens.**

   ```bash
   secretspec run --profile bootstrap -- nix run .#infra -- bootstrap apply
   secretspec run --profile bootstrap -- nix run .#infra -- bootstrap output -raw ci-apply \
     | secretspec set CLOUDFLARE_API_TOKEN --profile ci
   secretspec run --profile bootstrap -- nix run .#infra -- bootstrap output -raw agent-readonly \
     | secretspec set CLOUDFLARE_API_TOKEN --profile agent
   ```

   If the plan fails with *Unknown Cloudflare permission groups*, Cloudflare
   names one of them differently; fix the name in `tokens.nix`.

6. **Proton Pass agent tokens**, one per consumer, each limited to one vault:

   ```bash
   pass-cli agent create nix-images-ci   --vault nix-images-ci     --expiration 6m
   pass-cli agent create nix-images-plan --vault nix-images-agents --expiration 6m
   pass-cli agent create orca-fleet      --vault nix-images-agents --expiration 1m
   ```

   Each prints `PROTON_PASS_PERSONAL_ACCESS_TOKEN=pst_...`; keep the part after
   the `=`. `pass-cli agent monitor <name>` shows what each one read and why.

7. **GitHub.** Settings, Environments, new environment `cloudflare`, deployment
   branches limited to `master`, secret `PROTON_PASS_CI_TOKEN` (from
   `nix-images-ci`). Then a repository secret `PROTON_PASS_AGENT_TOKEN` (from
   `nix-images-plan`). Finally, the repository variable `INFRA_ENABLED` set to
   `true` switches the workflow on; until then both jobs are skipped.

8. **Existing records.** OpenTofu only manages what it created. Before declaring
   a record that already exists, import it (with the ci view, since import writes
   state), or delete it on the dashboard:

   ```bash
   secretspec run --profile ci -- nix run .#infra -- cloudflare import \
     'cloudflare_dns_record.www' '<zone id>/<record id>'
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

- Cloudflare Tunnel and Access (for God's Eye View on the Pi), Workers and
  Pages: the tokens already allow them; add the resources to `cloudflare.nix`.
- Proton itself has no API for domains or addresses, so the Proton side stays
  manual. Its DNS records are here (`settings.proton`).
