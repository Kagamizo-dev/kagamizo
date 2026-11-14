# browser: the Rust browser engine, and email aliases

Read CLAUDE.md first. Kind: browser-flow.

1. Choose the engine, recording each candidate as an adoption with its licence read at a pinned commit (2026-11-06 search):
   - obscura (Rust, Apache-2);
   - moli (Rust, Apache-2);
   - chromiumoxide (Rust, Apache-2, driving the pinned Chromium);
   - Lightpanda (Zig, AGPL-3): only as its own process, never linked.

   Port the chosen one's tests, and record the pick and why.
2. Email aliases need no browser: pass-cli has `alias` commands. A typed `identity.aliases` declares one alias per account sign-up, created by pass-cli and checked against Proton Pass.
3. The first flow is OpenRouter's credit purchase (upkeep/openrouter-topup-flow). Every flow declares its account, the pages it visits, what it types (only Proton Pass items) and the owner's 2FA step.
