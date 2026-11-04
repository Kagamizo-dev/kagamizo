/-
Discovery, proven to keep the repo liquid and free. Every role (an account
role, or a need no account fills yet) has candidates (../_data/candidates.json);
../default.nix renders them and Lean decides:

  * exits: every role a held account fills has a live alternative, a
    candidate that is not rejected and is not one of the providers already
    filling it, so no module is bound to one provider;
  * no new cost: an adopted candidate is free, on a free tier, or a
    provider whose account is already held (its payment declared there);
  * evidence: adopting or rejecting needs at least one dated finding.
-/
namespace Kagamizo.Scout

inductive Cost where
  | free | freeTier | usage | subscription
  deriving DecidableEq, Repr

inductive Status where
  | candidate | mapped | adopted | rejected
  deriving DecidableEq, Repr

structure Candidate where
  role : String
  name : String
  cost : Cost
  status : Status
  /-- Its provider has an account declared (accounts.held). -/
  held : Bool
  /-- It is not one of the providers already filling its role. -/
  alternative : Bool
  evidence : Nat

structure Role where
  name : String
  /-- How many held providers fill it today. -/
  heldProviders : Nat

def isExit (r : Role) (c : Candidate) : Bool :=
  c.role == r.name && c.status != .rejected && c.alternative

def exits (rs : List Role) (cs : List Candidate) : Bool :=
  rs.all fun r => r.heldProviders == 0 || cs.any (isExit r)

def addsNoCost (c : Candidate) : Bool :=
  c.status != .adopted || c.cost == .free || c.cost == .freeTier || c.held

def evidenced (c : Candidate) : Bool :=
  (c.status != .adopted && c.status != .rejected) || c.evidence > 0

def sound (rs : List Role) (cs : List Candidate) : Bool :=
  exits rs cs && cs.all addsNoCost && cs.all evidenced

/-- What the no-cost rule guarantees: in a sound registry, nothing adopted
is a subscription or a usage bill on an account not already held. -/
theorem adopted_costs_nothing_new (rs : List Role) (cs : List Candidate)
    (h : sound rs cs = true) (c : Candidate) (hc : c ∈ cs)
    (ha : c.status = .adopted) (hn : c.held = false) :
    c.cost = .free ∨ c.cost = .freeTier := by
  simp only [sound, Bool.and_eq_true] at h
  have := List.all_eq_true.mp h.1.2 c hc
  simp only [addsNoCost, ha, hn] at this
  cases hcost : c.cost <;> simp_all

-- What the rules refuse, on stand-ins.

/-- An adopted subscription with no account held. -/
example : sound [] [{ role := "r", name := "x", cost := .subscription, status := .adopted,
                      held := false, alternative := true, evidence := 1 }] = false := by
  decide

/-- A held role with no live alternative: the one candidate is rejected. -/
example : sound [{ name := "mail", heldProviders := 1 }]
    [{ role := "mail", name := "y", cost := .free, status := .rejected,
       held := false, alternative := true, evidence := 1 }] = false := by
  decide

/-- Adopting with no evidence. -/
example : sound [] [{ role := "r", name := "x", cost := .free, status := .adopted,
                      held := false, alternative := true, evidence := 0 }] = false := by
  decide

end Kagamizo.Scout
