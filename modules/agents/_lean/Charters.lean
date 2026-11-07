/-
The teams' checks and balances (modules/agents/charters.nix): every kind of
work names the team that proposes it, the teams that must pass it, and
whether the owner signs it off. ../charters.nix renders the declarations
after this file; Lean decides that no team reviews its own work, that every
kind is reviewed, that every trade is reviewed by both the legal and the
accounting swarm of the account's owner, that whatever goes live or moves
money needs the owner, and that every chartered team that proposes work is
reviewed by another team.
-/
namespace Kagamizo.Charters

structure Kind where
  name : String
  proposer : String
  reviewers : List String
  ownerSignsOff : Bool
  touches : List String
  deriving DecidableEq, Repr

/-- No team passes its own work, and someone always does. -/
def Kind.separated (k : Kind) : Bool :=
  !k.reviewers.contains k.proposer && !k.reviewers.isEmpty

/-- A trade is reviewed by the owner's legal and accounting swarms. -/
def Kind.tradeReviewed (owner : String) (k : Kind) : Bool :=
  !k.touches.contains "trade" ||
    (k.reviewers.contains ("legal-" ++ owner) && k.reviewers.contains ("accounting-" ++ owner))

/-- Going live or moving money waits for the owner. -/
def Kind.ownerGated (k : Kind) : Bool :=
  !(k.touches.contains "live" || k.touches.contains "money") || k.ownerSignsOff

/-- Spending involves the payer's accounting and legal teams, each as the
proposer or a reviewer. -/
def Kind.spendReviewed (payer : String) (k : Kind) : Bool :=
  let takesPart := fun t => k.proposer == t || k.reviewers.contains t
  !k.touches.contains "spend" ||
    (takesPart ("accounting-" ++ payer) && takesPart ("legal-" ++ payer))

def sound (owner : String) (ks : List Kind) : Bool :=
  ks.all fun k => k.separated && k.tradeReviewed owner && k.ownerGated

/-- Every chartered team that proposes some kind is passed by another team. -/
def proposersReviewed (ks : List Kind) (teams : List String) : Bool :=
  teams.all fun t =>
    ks.all fun k => k.proposer != t || k.reviewers.any (· != t)

/-- A separated kind's proposer is never among its reviewers. -/
theorem separated_not_self (k : Kind) (h : k.separated = true) :
    k.proposer ∉ k.reviewers := by
  unfold Kind.separated at h
  simp [Bool.and_eq_true] at h
  simpa using h.1

end Kagamizo.Charters
