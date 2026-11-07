/-
The bank module's paper: the owner's own bank as one app.
Checked by checks.paper-bank (modules/repo/papers.nix).
-/
open Kagamizo.Paper

def paper : Paper := {
  module := "bank",
  title := "A personal bank as one typed app: legal and tax identity bound to every source of revenue",
  abstract := "The bank module gathers what was spread across modules (the treasury on Mercury, the brokerages on Public and IBKR, trading, the books and tax, the credit lines, the legal record, the registered agent and the rules) into one app whose services each name the module that runs them, the accounts they hold and the teams that run them. Lean decides that every account holding money belongs to a service and that every source of revenue lands in its own entity's account, for an entity that is taxed and whose obligations are declared.",
  authors := ["accounting-jingzo", "legal-jingzo"],
  date := "2026-11-07",
  sections := [
    { kind := .purpose,
      body := "The owner wants one place for everything about money and the law: where revenue comes from, which entity earns it, which account it lands in, what is owed to whom and when, and who is responsible. Before this module the answer was spread across a dozen modules (mercury, public, ibkr, trading, money, legal, northwest, compliance and the card issuers), each correct alone, none of them saying how they fit. The bank is that fit: legal and tax identity bound to every source of revenue, with every flow in and out, foreign accounts and loans between entities to come, going through one app, as if the owner ran a bank of their own.",
      cites := ["pacioli-summa"] },
    { kind := .lifecycle,
      body := "Declared: bank.services (each with its module, role, accounts and teams) and bank.revenue (each source with its entity, account, where it lands on a return and whether that treatment is settled). The services' own modules keep their declarations: money.tax and money.obligations, money.flows and floors, the legal records, the compliance rules, the strategies and their limits. Changed: a new account, a new revenue source or a new service is a change of kind code, reviewed by the accountants and the lawyers; anything that moves money stays the owner's approval, as money.flows already requires. Retired: an account closed at its provider is removed from its service in the same commit, and Lean refuses a money account that no service holds.",
      cites := ["pacioli-summa"] },
    { kind := .pipeline,
      body := "checks.bank renders every money account (an account at a provider that holds or moves money or records credit), the owner of every held account, the services, the revenue sources, the taxed entities and the entities with declared obligations as Lean facts, and decides bank_sound by the kernel on every push. packages.bank-book renders the bank as JSON: services, revenue, accounts by entity, the declared flows and the year's obligations with their dates. The Bank card in the shell shows the same data, with what waits on the owner first, read from the plan's bank and trading tracks. The services' own checks (money, compliance, trading's stages and risk, legal) run beside it.",
      cites := ["lean4"] },
    { kind := .agents,
      body := "The bank's accountants are accounting-jingzo and accounting-mirazo, which keep the treasury, the brokerages, the books, the tax and the credit; its lawyers are legal-jingzo and legal-mirazo, which keep the legal record, the registered agent and, with the governance swarms, the rules; research-jingzo runs the strategies under the trading service. Each team acts as a scoped user: it reads through governed wrappers and never spends, signs in or signs up; the owner, as root admin, approves every flow that moves money and every sign-in, and dates every promotion of a strategy to live trading.",
      cites := ["pacioli-summa"] },
    { kind := .tools,
      body := "The bank runs through its services' tools, all governed by Cedar: mercury-cli and cards for the treasury; brokerage (Public) for reads; trade for proposals, paper days and settlement; ledger for the nightly brokerage books; tax-report for a year's journal, Schedule C and obligations; legal-documents and legal-sync for the record; northwest for the registered agent. The bank itself adds packages.bank-book and the Bank card, and its check. Browser flows are the last resort for providers with no API, and agents run them only as typed, governed flows.",
      cites := ["lean4"] },
    { kind := .data,
      body := "The bank's data is its declarations and what its services read: the held accounts and their owners (Mirazo's eight money accounts, Jingzo's four, Kagamizo's two on 2026-11-07), the year's obligations from money.obligations with their dates and sources, and the declared flows. Balances and transactions are read from the providers at run time and kept on the host or in Proton Drive, never in the repository, which is public; values such as EINs and account numbers live only in Proton Pass and are rendered into documents at run time.",
      cites := ["pacioli-summa"] },
    { kind := .design,
      body := "The bank composes instead of rebuilding: a service is a pointer to the module that runs it, with the accounts it holds and the teams that run it, so the books stay in money, the rules in compliance and the strategies in trading. The shell's library gains services (modules shown inside another app), so the bank's modules leave the home column and appear inside the Bank card. Lean's sourceOk ties a revenue source to its entity three ways: the account it lands in is the entity's own, the entity is taxed (money.tax), and the entity owes declared obligations (money.obligations); sound adds that every money account is held by a service, and every service's teams exist.",
      cites := ["lean4", "pacioli-summa"] },
    { kind := .guarantees,
      body := "checks.bank decides bank_sound for the declared bank: services and sources are uniquely named; every money account is held by at least one service, so no money sits outside the bank; every revenue source lands in an account its own entity holds, for an entity that is taxed and has declared obligations; and every service is run by chartered teams. Every declared status (filed, paid, not owed or extended) names an obligation the bank knows and shows its evidence; an obligation with no status that falls due before the bank's as-of date is listed as past due, first among what waits on the owner. The theorem source_taxed proves that any source passing sourceOk belongs to a taxed entity, so no income can be declared for an entity the bank does not file for.",
      cites := ["lean4"] },
    { kind := .performance,
      body := "No perf target is declared. The check decides over thirty held accounts, ten services and two revenue sources in seconds. What will matter is the ledger: when the bank keeps one double-entry ledger of every flow, the time from a transaction at a provider to its entry in the books, and to its treatment on a return, becomes the measure, with a target that it lands the same night.",
      cites := ["pacioli-summa"] },
    { kind := .priorWork,
      body := "Double-entry bookkeeping, set out by Pacioli in 1494, is the model the bank's ledger will follow: every flow is a debit in one account and a credit in another, so the books balance by construction. Nix's purely functional deployment, after Dolstra, is why the bank is a value built from declarations and checked before it is used, and Lean 4 decides its soundness by the kernel. Enterprise resource planning systems keep finance, legal and operations in one schema; the bank does the same for one person's entities, with the schema typed and its rules proved.",
      cites := ["pacioli-summa", "dolstra-thesis", "lean4"] },
    { kind := .gaps,
      body := "There is no single double-entry ledger yet: the books are a year's journal built on demand from Mercury and a nightly brokerage read, and the bank's ledger of every flow, loans between entities included, is the plan's next bank item. The treatment of the weather strategy's event contracts on a return, and of research income, is not settled. Wyoming's annual report has no date until Jingzo's formation date is in its record. Foreign accounts and currencies are not declared. The registered agent's documents are not read into the app until Northwest's CLI can sign in. The bank's page is the shell's module page with sections, not yet a page of its own.",
      cites := ["pacioli-summa"] }
  ],
  citations := [
    { key := "pacioli-summa", title := "Summa de arithmetica, geometria, proportioni et proportionalita", authors := ["Luca Pacioli"], year := 1494,
      source := .url "https://archive.org/details/summa-de-arithmetica-geometria-proportioni-et-proportionalita" },
    { key := "dolstra-thesis", title := "The Purely Functional Software Deployment Model", authors := ["Eelco Dolstra"], year := 2006,
      source := .url "https://edolstra.github.io/pubs/phd-thesis.pdf" },
    { key := "lean4", title := "The Lean 4 Theorem Prover and Programming Language", authors := ["Leonardo de Moura", "Sebastian Ullrich"], year := 2021,
      source := .doi "10.1007/978-3-030-79876-5_37" }
  ],
  theorems := ["source_taxed"],
  perf := [],
  checks := ["bank", "paper-bank", "money-flows"],
  packages := ["bank-book"],
  agents := ["accounting-jingzo", "accounting-mirazo", "legal-jingzo", "legal-mirazo", "research-jingzo", "governance-jingzo", "governance-mirazo"]
}
