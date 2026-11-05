/-
What `brokerage` may run, checked against Public's pinned CLI
(Api/Public, rendered from catalog/_json/public.json): the calls the
wrappers make are accepted, and calls that are not the CLI's are refused.
The Rust gate (modules/lean/_src, `api-check`) decides the same for the
words `brokerage` is given at run time.
-/
namespace Kagamizo.Public
open Kagamizo.Api

/-- `brokerage summary`: accounts, then the default account's portfolio. -/
theorem summary_accepted :
    Public.api.accepts { op := "accounts list", given := [] } = true ∧
    Public.api.accepts { op := "portfolio show", given := [] } = true := by
  decide +kernel

/-- `trade bars` reads Public's bars for one symbol. -/
theorem bars_accepted :
    Public.api.accepts { op := "historicdata bars", given := [("security-type", .str "EQUITY"), ("symbol", .str "SPY"), ("period", .str "YEAR")] } = true := by
  decide +kernel

/-- A command the CLI does not have is refused, whatever it gives. -/
theorem unknown_refused :
    Public.api.accepts { op := "accounts drain", given := [] } = false := by
  decide +kernel

/-- An option the command does not take is refused. -/
theorem unknown_option_refused :
    Public.api.accepts { op := "accounts list", given := [("withdraw", .set)] } = false := by
  decide +kernel

/-- Placing an order needs its order file: without it, refused. -/
theorem order_needs_file :
    Public.api.accepts { op := "order place", given := [] } = false := by
  decide +kernel

/-- Naming the account does not stand in for the file: still refused. -/
theorem order_needs_file_even_with_account :
    Public.api.accepts { op := "order place", given := [("account-id", .str "5OI41709"), ("yes", .set)] } = false := by
  decide +kernel

/-- With its file, `order place` is a call the CLI takes (governance, not the
model, is what keeps it the controller's). -/
theorem order_with_file_accepted :
    Public.api.accepts { op := "order place", given := [("file", .str "order.json"), ("account-id", .str "5OI41709")] } = true := by
  decide +kernel

/-- `trade propose spy-agents` reads one expiration's chain on the brokerage
account, as `brokerage market option-chain SPY 2026-11-20` sends it. -/
theorem option_chain_accepted :
    Public.api.accepts { op := "market option-chain", given := [("symbol", .str "SPY"), ("expiration-date", .str "2026-11-20"), ("account-id", .str "5OI41709")] } = true := by
  decide +kernel

/-- The chain needs its expiration: the symbol alone is refused. -/
theorem option_chain_needs_expiration :
    Public.api.accepts { op := "market option-chain", given := [("symbol", .str "SPY")] } = false := by
  decide +kernel

/-- `trade propose weather-rules` reads one category's event summaries, as
`brokerage event-contracts summary --category "Climate and Weather"` does;
the command takes no account. -/
theorem event_summary_accepted :
    Public.api.accepts { op := "event-contracts summary", given := [("category", .str "Climate and Weather"), ("sort", .str "VOLUME")] } = true ∧
    Public.api.accepts { op := "event-contracts summary", given := [("account-id", .str "5OI41709")] } = false := by
  decide +kernel

/-- `ledger public` (modules/money): the portfolio, the history and the
orders of the brokerage account, every one a read the wrapper sends with
`--json` and `--account-id`. -/
theorem ledger_reads_accepted :
    Public.api.accepts { op := "portfolio show", given := [("json", .set), ("account-id", .str "5OI41709")] } = true ∧
    Public.api.accepts { op := "history list", given := [("json", .set), ("account-id", .str "5OI41709"), ("page-size", .int 100)] } = true ∧
    Public.api.accepts { op := "order search", given := [("json", .set), ("account-id", .str "5OI41709")] } = true ∧
    Public.api.accepts { op := "taxlots list", given := [("json", .set), ("account-id", .str "5OI41709")] } = true := by
  decide +kernel

end Kagamizo.Public
