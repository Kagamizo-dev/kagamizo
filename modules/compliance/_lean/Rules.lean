/-
The rules the owner trades under (modules/compliance/rules.nix), as far as
they are machine-checkable: FINRA's pattern-day-trader rule (Rule
4210(f)(8)(B): four or more day trades in five business days in a margin
account holding under $25,000 is a pattern day trader, and the account is
restricted) and the options level a strategy's trades need, as Public and
its clearing firm grant them (level 1 covered calls, level 2 long calls and
puts, level 3 spreads). `pdtSafe` and `optionsLevelOk` are the rules every
declared strategy is held to against the account it runs on, as observed;
the theorems are what they guarantee. ../rules.nix renders the observed
accounts and the declared strategies after this file and Lean decides them.
-/
namespace Kagamizo.Compliance

/-- A strategy's stage (modules/trading/stages.nix). -/
inductive Stage where
  | research
  | backtest
  | paper
  | live
  deriving DecidableEq, Repr

/-- What a strategy trades. -/
inductive Instrument where
  | equity
  | option
  | eventContract
  | crypto
  | bond
  deriving DecidableEq, Repr

/-- A brokerage account as observed through its API on a given day. -/
structure Account where
  name : String
  margin : Bool
  equityUsd : Nat
  optionsLevel : Nat
  deriving DecidableEq, Repr

structure Strategy where
  name : String
  instrument : Instrument
  /-- The most round trips it can open and close on one day, over five
  business days (trading.strategies.<s>.maxDayTradesPer5Days). -/
  maxDayTradesPer5Days : Nat
  /-- The options level its trades need: 0 when it trades no option. -/
  needsOptionsLevel : Nat
  stage : Stage
  deriving DecidableEq, Repr

/-- FINRA Rule 4210(f)(8)(B): the equity below which a pattern day trader
is restricted, and the most day trades in five business days that do not
make one. -/
def pdtEquityUsd : Nat := 25000
def pdtMaxDayTrades : Nat := 3

/-- A strategy is safe from the pattern-day-trader rule on an account when
the account is not a margin account, or holds the equity, or the strategy
never reaches four day trades in five business days. -/
def pdtSafe (a : Account) (s : Strategy) : Bool :=
  !a.margin || a.equityUsd ≥ pdtEquityUsd || s.maxDayTradesPer5Days ≤ pdtMaxDayTrades

/-- Paper and live stages send orders to the broker (paper preflights
them); research and backtest touch no account. -/
def Stage.ordersAtBroker : Stage → Bool
  | .research => false
  | .backtest => false
  | .paper => true
  | .live => true

/-- A strategy that sends orders to the broker has the options level its
trades need; one that does not may be declared ahead of the level. -/
def optionsLevelOk (a : Account) (s : Strategy) : Bool :=
  s.needsOptionsLevel ≤ a.optionsLevel || !s.stage.ordersAtBroker

/-- On a margin account under the equity, a pdt-safe strategy makes at most
three day trades in five business days: it is never a pattern day trader. -/
theorem pdtSafe_bounds_day_trades (a : Account) (s : Strategy)
    (hm : a.margin = true) (he : a.equityUsd < pdtEquityUsd)
    (h : pdtSafe a s = true) : s.maxDayTradesPer5Days ≤ pdtMaxDayTrades := by
  simp only [pdtSafe, hm, Bool.not_true, Bool.false_or, Bool.or_eq_true,
    decide_eq_true_eq] at h
  omega

/-- A live strategy has the options level its trades need. -/
theorem live_has_level (a : Account) (s : Strategy) (hl : s.stage = .live)
    (h : optionsLevelOk a s = true) : s.needsOptionsLevel ≤ a.optionsLevel := by
  simp only [optionsLevelOk, hl, Stage.ordersAtBroker, Bool.not_true, Bool.or_false,
    decide_eq_true_eq] at h
  exact h

/-- So does a paper strategy: its preflights go to the broker. -/
theorem paper_has_level (a : Account) (s : Strategy) (hp : s.stage = .paper)
    (h : optionsLevelOk a s = true) : s.needsOptionsLevel ≤ a.optionsLevel := by
  simp only [optionsLevelOk, hp, Stage.ordersAtBroker, Bool.not_true, Bool.or_false,
    decide_eq_true_eq] at h
  exact h

/-- A strategy that trades no option (needs level 0) is fine on any account
at any stage. -/
theorem no_option_ok (a : Account) (s : Strategy) (h0 : s.needsOptionsLevel = 0) :
    optionsLevelOk a s = true := by
  simp [optionsLevelOk, h0]

end Kagamizo.Compliance
