/-
Delegation, proven complete. Every area of work (organization.areas: an
entity's mailbox role) has an owner agent unless it is a person's own
(zach@), and every agent owns or reviews some area, so no team sits idle
and no area is nobody's. ../default.nix renders both and Lean decides it.
No self-review and classes within the owner's are ../organization's
theorems; budgets are ../agents'.
-/
namespace Kagamizo.Team

structure Area where
  name : String
  owner : Option String
  reviewers : List String
  /-- The owner's own address (zach@), which has no agent owner by design. -/
  personal : Bool

def hasWork (as : List Area) (agent : String) : Bool :=
  as.any fun a => a.owner == some agent || a.reviewers.contains agent

def owned (a : Area) : Bool := a.personal || a.owner.isSome

def delegated (agents : List String) (as : List Area) : Bool :=
  agents.all (hasWork as) && as.all owned

theorem delegated_no_idle (agents : List String) (as : List Area)
    (h : delegated agents as = true) (n : String) (hn : n ∈ agents) :
    hasWork as n = true := by
  simp only [delegated, Bool.and_eq_true] at h
  exact List.all_eq_true.mp h.1 n hn

-- What the rule refuses, on stand-ins.

/-- An agent with no area. -/
example : delegated ["idle"] [{ name := "k/dev", owner := some "upkeep", reviewers := [], personal := false }] = false := by
  decide

/-- An area that is nobody's. -/
example : delegated [] [{ name := "k/admin", owner := none, reviewers := [], personal := false }] = false := by
  decide

end Kagamizo.Team
