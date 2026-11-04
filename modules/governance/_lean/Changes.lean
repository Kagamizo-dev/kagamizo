/-
How a change to the repository is classed, and who may merge it
(modules/governance/changes.nix). Every path a pull request touches falls
in one class; a pull request's classes are all of them, and an agent may
merge only when every one is a class agents may merge. A class agents may
never touch (infra, secret, spend) makes the whole request theirs to
refuse. ../changes.nix renders the table after this file, and Lean decides
its shape: one class is the agents' own, the rest wait for the owner or
are never an agent's.
-/
namespace Kagamizo.Changes

inductive Merge where
  /-- Agents merge it themselves once the checks pass. -/
  | agent
  /-- The owner approves it in the request (one tap: an approve-sign-in step). -/
  | owner
  /-- Never from an agent's branch. -/
  | never
  deriving DecidableEq, Repr

structure Class where
  name : String
  merge : Merge
  deriving DecidableEq, Repr

/-- An agent may merge a request only when every class it touches is theirs. -/
def agentMayMerge (touched : List Class) : Bool :=
  !touched.isEmpty && touched.all (·.merge == .agent)

/-- A request that touches a class agents never hold is refused outright. -/
def refused (touched : List Class) : Bool := touched.any (·.merge == .never)

/-- What an agent may merge is never what is refused: the two decisions can
not both hold of one request. -/
theorem merge_not_refused (touched : List Class) (h : agentMayMerge touched = true) :
    refused touched = false := by
  unfold agentMayMerge at h
  have hall := (Bool.and_eq_true _ _).mp h |>.2
  unfold refused
  rw [List.any_eq_false]
  intro c hc
  have := List.all_eq_true.mp hall c hc
  simp only [beq_iff_eq] at this
  simp [this]

/-- Adding any class to a request never widens what an agent may merge. -/
theorem merge_mono (touched : List Class) (c : Class)
    (h : agentMayMerge (c :: touched) = true) : c.merge = .agent := by
  unfold agentMayMerge at h
  have hall := (Bool.and_eq_true _ _).mp h |>.2
  have := List.all_eq_true.mp hall c (List.mem_cons_self ..)
  simpa using this

end Kagamizo.Changes
