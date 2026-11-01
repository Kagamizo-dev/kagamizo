# Catalogs

Every tool and API the modules use, as its pinned version states it
(`./_json`, extracted from the pin itself; `../lean` renders each into
Lean). Generated from `sources.nix`: `nix run .#catalog-readme`.

| Catalog | From | Version |
|---|---|---|
| bridge | protonmail-bridge source (nixpkgs) | 3.24.2 |
| cdp | the pinned Chromium's /json/protocol | Chromium 155.0.8059.84, protocol 1.3 |
| cf | npm `cf` | 1.0.0-beta.13 |
| cloudflare-provider | OpenTofu cloudflare/cloudflare provider (nixpkgs) | 5.19.1 |
| gh | gh (nixpkgs) | 2.102.0 |
| hcloud | hcloud | 1.64.1 |
| hetzner-api | docs.hetzner.cloud/cloud.spec.json (unversioned upstream) | sha256 772d662e1336ea01…, Tue, 27 Oct 2026 14:17:08 GMT |
| hetzner-provider | OpenTofu hetznercloud/hcloud provider (nixpkgs) | 1.63.0 |
| mercury | MercuryTechnologies/mercury-cli | v0.11.8 (25cc254e78ed) |
| mercury-api | MercuryTechnologies/mercury-go, as mercury-cli's go.mod requires | v0.13.11 |
| pass-cli | pass-cli release binary | 2.4.2 |
| pass-items | pass-cli's templates, read with a session; app templates as observed | 2.4.2 (app templates: api-credential, Mirazo-Root/Public, an API credential made in the Proton Pass app (2026-10-31)) |
| public | PublicDotCom/publicdotcom-cli | v1.3.7 (bac3f08ca76a) |
| rea | morluto/rea | rea-agents-6.7.0 (27dc42d10249) |

Two have no upstream versions and are stamped by content instead:
Hetzner's OpenAPI spec (its SHA-256 and Last-Modified;
`nix run .#hetzner-api-update`) and Proton Pass's app templates (the
item and date each was read from).
