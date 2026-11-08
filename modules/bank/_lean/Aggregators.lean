/-
Which service the bank reads Chase, Capital One and Credit One through
(modules/bank/aggregators.nix). The owner's rule (2026-11-08): confirm a
service covers everything before choosing it. A provider is acceptable
when it allows linking one's own accounts and every required institution
is covered, with card transactions, by a fact verified from the
provider's own institution search, or is a gap the owner accepted by name.
-/
namespace Kagamizo.Aggregators

inductive Fact where
  | yes
  | no
  | unknown
  deriving DecidableEq, Repr

structure Coverage where
  institution : String
  supported : Fact
  /-- Card transactions; `yes` too for an institution with no cards. -/
  cardTransactions : Fact
  /-- Read from the provider's own search, on a date. -/
  verified : Bool
  deriving Repr

structure Provider where
  name : String
  ownAccounts : Fact
  coverage : List Coverage
  deriving Repr

/-- An institution the provider covers, by a verified fact. -/
def covers (p : Provider) (i : String) : Bool :=
  p.coverage.any (fun c => c.institution == i && c.supported == .yes && c.cardTransactions == .yes && c.verified)

/-- A provider is acceptable when own accounts are allowed and every
required institution is covered or accepted as a gap. -/
def acceptable (p : Provider) (required accepted : List String) : Bool :=
  p.ownAccounts == .yes && required.all (fun i => covers p i || accepted.contains i)

/-- An acceptable provider covers, by verified fact, every required
institution the owner did not accept as a gap. -/
theorem acceptable_covers (p : Provider) (required accepted : List String)
    (h : acceptable p required accepted = true) (i : String) (hi : i ∈ required)
    (hn : accepted.contains i = false) : covers p i = true := by
  simp only [acceptable, Bool.and_eq_true, List.all_eq_true] at h
  have := h.2 i hi
  simp only [Bool.or_eq_true] at this
  rcases this with h1 | h2
  · exact h1
  · exfalso
    have hc : accepted.contains i = true := h2
    rw [hn] at hc
    exact Bool.false_ne_true hc

/-- Nothing unverified is ever acceptable coverage. -/
theorem unverified_covers_nothing (p : Provider) (i : String)
    (h : p.coverage.all (fun c => !c.verified) = true) : covers p i = false := by
  simp only [covers, List.any_eq_false]
  intro c hc
  simp only [List.all_eq_true] at h
  have := h c hc
  simp_all

end Kagamizo.Aggregators
