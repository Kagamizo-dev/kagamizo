/-
Agent identities, proven sound. Every agent (governance.agents) is in one
team (governance.teams); ../default.nix renders both lists and has Lean
decide `sound` over them, so a declaration that breaks a rule fails
`checks.team-lean`, naming nothing but the rule: the Nix side names the
field (governance.problems).

The rules, for every agent:
  * it serves its team's entity, when the team serves one;
  * its tier is at or below its team's cap;
  * it never reviews its own team;
  * an agent of a review team reviews some team and proposes no change;
  * its model key is its own entity's (the profile swarm-<entity>).
-/
namespace Kagamizo.Team

structure Team where
  name : String
  serves : Option String
  review : Bool
  capRank : Nat

structure Agent where
  name : String
  serves : String
  team : String
  tierRank : Nat
  keyProfile : String
  changeClasses : List String
  reviews : List String

def teamOf (ts : List Team) (a : Agent) : Option Team :=
  ts.find? (·.name == a.team)

/-- It serves its team's entity (any entity, for a team every entity has). -/
def inTeamEntity (ts : List Team) (a : Agent) : Bool :=
  match teamOf ts a with
  | none => false
  | some t => match t.serves with
    | none => true
    | some e => e == a.serves

def withinCap (ts : List Team) (a : Agent) : Bool :=
  match teamOf ts a with
  | none => false
  | some t => decide (a.tierRank ≤ t.capRank)

def noSelfReview (a : Agent) : Bool :=
  !(a.reviews.contains a.team)

/-- A reviewer reviews someone and proposes nothing. -/
def reviewerOnlyReviews (ts : List Team) (a : Agent) : Bool :=
  match teamOf ts a with
  | none => false
  | some t => !t.review || (a.changeClasses.isEmpty && !a.reviews.isEmpty)

def ownKey (a : Agent) : Bool :=
  a.keyProfile == "swarm-" ++ a.serves

def agentSound (ts : List Team) (a : Agent) : Bool :=
  inTeamEntity ts a && withinCap ts a && noSelfReview a &&
    reviewerOnlyReviews ts a && ownKey a

def sound (ts : List Team) (as : List Agent) : Bool :=
  as.all (agentSound ts)

/-- Soundness gives each rule for every agent; here, the one the review gate
rests on: no agent of a sound declaration reviews its own team. -/
theorem sound_no_self_review (ts : List Team) (as : List Agent)
    (h : sound ts as = true) (a : Agent) (ha : a ∈ as) :
    noSelfReview a = true := by
  have := List.all_eq_true.mp h a ha
  simp only [agentSound, Bool.and_eq_true] at this
  exact this.1.1.2

/-- ... and no agent of a sound declaration uses another entity's key. -/
theorem sound_own_key (ts : List Team) (as : List Agent)
    (h : sound ts as = true) (a : Agent) (ha : a ∈ as) :
    ownKey a = true := by
  have := List.all_eq_true.mp h a ha
  simp only [agentSound, Bool.and_eq_true] at this
  exact this.2

-- What the rules refuse, on stand-ins.
private def tRev : Team := { name := "review", serves := some "k", review := true, capRank := 2 }
private def tWork : Team := { name := "work", serves := some "k", review := false, capRank := 2 }

/-- An agent reviewing its own team is refused. -/
example : sound [tRev, tWork]
    [{ name := "a", serves := "k", team := "work", tierRank := 2,
       keyProfile := "swarm-k", changeClasses := [], reviews := ["work"] }] = false := by
  decide

/-- A reviewer that proposes a change is refused. -/
example : sound [tRev, tWork]
    [{ name := "r", serves := "k", team := "review", tierRank := 2,
       keyProfile := "swarm-k", changeClasses := ["content"], reviews := ["work"] }] = false := by
  decide

/-- An agent above its team's cap, or on another entity's key, is refused. -/
example : sound [tWork]
    [{ name := "a", serves := "k", team := "work", tierRank := 3,
       keyProfile := "swarm-k", changeClasses := [], reviews := [] }] = false := by
  decide
example : sound [tWork]
    [{ name := "a", serves := "k", team := "work", tierRank := 2,
       keyProfile := "swarm-j", changeClasses := [], reviews := [] }] = false := by
  decide

end Kagamizo.Team
