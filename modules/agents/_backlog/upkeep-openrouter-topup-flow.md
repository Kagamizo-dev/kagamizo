# upkeep: a browser flow for OpenRouter credit

Read CLAUDE.md first. Kind: account-limit (accounting-jingzo, legal-jingzo and review pass it).

OpenRouter has no API to buy credit: `POST /credits/coinbase` is deprecated in favour of the web purchase flow (openapi.json, 2026-11-06). The owner allows accounting to top up within the Mercury card's limit (the credit-topup lifecycle).

1. Build the top-up as a flow in modules/browser, the pinned Chromium driven over CDP from Rust. It signs in with the openrouter login item through Proton Pass and opens the credits page. It buys the amount in a declared `openrouter.topUpUsd` (at most the card's remaining limit, checked by Lean). If OpenRouter asks for 2FA, the owner approves it.
2. The flow runs only as accounting-jingzo, after the credit-topup lifecycle's reviews pass. Cedar's agents-never-spend rule needs a dated, owner-approved exception for exactly this action (`openrouter:credit-topup`) and no other. Write it so the Cedar tests prove nothing else gains spend.
3. Remove the Gap in modules/cloudflare/README.md once it works end to end.
