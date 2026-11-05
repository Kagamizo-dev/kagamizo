/-
Resources priced like an order book. Each class (tokens, cpu, gpu, ...) has
rates from one or more providers (../_data/rates.json); `chosen` names the
one we use. ../default.nix renders them and Lean decides:

  * a chosen provider is one of the class's rates (never a phantom);
  * where a class has two or more rates, the chosen one is the cheapest, or
    within a capped premium of it with a stated reason (the supply module's
    stability-over-price rule, reused for the market).

A class with no chosen provider, or only one rate, is not a failure: it is a
gap the CLI surfaces (no competition, or nothing picked yet), the way scout
surfaces a role with no exit.
-/
namespace Kagamizo.Market

structure Rate where
  cls : String
  provider : String
  /-- Price in micro-dollars per the class's unit, so the maths is on Nat. -/
  micros : Nat

structure Chosen where
  cls : String
  provider : String
  /-- A reason is required to pick other than the cheapest. -/
  reason : String

def ratesOf (rs : List Rate) (c : String) : List Rate :=
  rs.filter (·.cls == c)

def cheapest (rs : List Rate) (c : String) : Option Nat :=
  (ratesOf rs c).foldl (fun m r => some (min (m.getD r.micros) r.micros)) none

/-- The chosen provider exists for its class, and either it is within a
capped premium of the cheapest, or the class has a single rate, or a reason
is given and it is at most twice the cheapest. -/
def soundChoice (rs : List Rate) (capPct : Nat) (ch : Chosen) : Bool :=
  match (ratesOf rs ch.cls).find? (·.provider == ch.provider) with
  | none => false
  | some r =>
    match cheapest rs ch.cls with
    | none => false
    | some lo =>
      decide ((ratesOf rs ch.cls).length < 2) ||
      decide (r.micros * 100 ≤ lo * (100 + capPct)) ||
      (ch.reason != "" && decide (r.micros ≤ lo * 2))

def sound (rs : List Rate) (capPct : Nat) (chs : List Chosen) : Bool :=
  chs.all (soundChoice rs capPct)

-- What the rule refuses, on stand-ins.
private def two : List Rate :=
  [{ cls := "t", provider := "a", micros := 100 },
   { cls := "t", provider := "b", micros := 300 }]

/-- Picking the dearer of two, no reason, past the cap: refused. -/
example : sound two 25 [{ cls := "t", provider := "b", reason := "" }] = false := by decide
/-- The cheaper is always fine. -/
example : sound two 25 [{ cls := "t", provider := "a", reason := "" }] = true := by decide
/-- Within the cap is fine with no reason. -/
example : sound [{ cls := "t", provider := "a", micros := 100 },
                 { cls := "t", provider := "b", micros := 120 }]
    25 [{ cls := "t", provider := "b", reason := "" }] = true := by decide
/-- A reason admits a premium up to twice the cheapest, not beyond. -/
example : sound two 25 [{ cls := "t", provider := "b", reason := "stable" }] = false := by decide
example : sound [{ cls := "t", provider := "a", micros := 100 },
                 { cls := "t", provider := "b", micros := 180 }]
    25 [{ cls := "t", provider := "b", reason := "stable" }] = true := by decide
/-- A phantom provider is refused. -/
example : sound two 25 [{ cls := "t", provider := "z", reason := "x" }] = false := by decide

end Kagamizo.Market
