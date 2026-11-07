# upkeep: every request to the owner is a Proton Pass link

Read CLAUDE.md first. Kind: code.

The owner's rule of 2026-11-06:
- anything that needs the owner (a payment, a sign-up, a 2FA approval, a card) reaches them as a link, in Matrix's #owner room;
- everything they need for it is in Proton Pass.

Make it typed.

1. `accounts.held.<a>.links` (modules/accounts/options.nix):
   - `signIn` (URL);
   - `billing` (URL; required when the plan's billing is not free);
   - `twoFactor`, with `method` as an enum: passkey, totp, email, sms, app, push or none.

   When the method is email, `twoFactor.inbox` names the declared mailbox, and the link is Proton Mail's inbox for it.
2. Fill them from Proton Pass, not from memory: read each account's login item's URLs as metadata with `pass-cli item view --output json`. Never print a field's value; take only `urls` and the item and share ids. Write a Rust reader for that (no shell), and a check that the declared links match the items' URLs.
3. `owner.request <account> <what>` (Rust) renders the deep links:
   - the item, as Proton Pass's own route: `https://pass.proton.me/u/0/share/<shareId>/item/<itemId>`, read from WebClients' routing.ts (`getItemRoute`);
   - the account's billing or sign-in page;
   - the Proton Mail inbox where the code arrives.

   It posts them to #owner once the Matrix bots exist (backlog upkeep/matrix-bots), and until then prints them for the session to send as a file card.
4. Lean: every billed account has a billing link; every account whose 2FA is email names a declared mailbox.

Run it as a ratchet if needed, as `checks.languages` does: dated exceptions that only shrink.
