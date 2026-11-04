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

end Kagamizo.Public
