/-
Money, typed for tax (modules/money). Every transaction category Mercury's
pinned SDK has gets a treatment; every entity has a classification, and a
disregarded one's activity is on its owner's return; every account on a
paid plan names what pays it. ../default.nix renders the declarations and
Lean decides them.
-/
namespace Kagamizo.Money

inductive Treatment where
  /-- A Schedule C (Form 1040) Part II line, and the percent deductible. -/
  | scheduleC (line : String) (percent : Nat)
  | personal
  | nondeductible
  /-- Settled per transaction, by a person: listed in the report. -/
  | review
  deriving DecidableEq, Repr

def Treatment.deductible : Treatment → Nat
  | .scheduleC _ p => p
  | _ => 0

inductive Classification where
  | individual
  | disregarded (owner : String)
  | sCorp
  | partnership
  | cCorp
  deriving DecidableEq, Repr

structure Profile where
  entity : String
  classification : Classification
  deriving Repr

/-- Whose return an entity's activity is on, following owners (at most
`fuel` steps, enough for any declared chain). -/
def returnOf (ps : List Profile) : Nat → String → String
  | 0, e => e
  | fuel + 1, e =>
    match ps.find? (·.entity == e) with
    | some ⟨_, Classification.disregarded o⟩ => returnOf ps fuel o
    | _ => e

/-- Every chain of owners ends at an entity that files its own return. -/
def Profile.filesOwn (p : Profile) : Bool :=
  match p.classification with
  | .disregarded _ => false
  | _ => true

def lands (ps : List Profile) : Bool :=
  ps.all fun p => (ps.find? (·.entity == returnOf ps ps.length p.entity)).all Profile.filesOwn

inductive Billing where
  | free
  | subscription
  | usage
  deriving DecidableEq, Repr

structure Account where
  name : String
  billing : Billing
  /-- It names one thing that pays it (a card, the owner's card, a waiver,
  or a declared Gap). -/
  paid : Bool
  deriving Repr

def Account.payable (a : Account) : Bool := a.billing == .free || a.paid

/-- A paid treatment never deducts more than it costs, and meals half. -/
theorem deductible_le (t : Treatment) (h : ∀ l p, t = .scheduleC l p → p ≤ 100) :
    t.deductible ≤ 100 := by
  cases t with
  | scheduleC l p => exact h l p rfl
  | _ => simp [Treatment.deductible]

end Kagamizo.Money
