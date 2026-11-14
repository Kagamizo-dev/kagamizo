/-
Readiness for live trading (../readiness.nix): every step of the live
lifecycle with what exercises it. The rule: a strategy is at stage live only
when every step has run against Public's real backend, every paper day or
once by a deliberate canary order; a step proved only against the stub, or
not at all, keeps every strategy short of live. So the switch to live is a
setting, never the first time a piece of wiring meets the real backend.
-/
namespace Kagamizo.Readiness

inductive Exercised where
  | real | realOnce | stub | none
  deriving DecidableEq, Repr

structure Step where
  name : String
  exercised : Exercised
  deriving DecidableEq, Repr

def realStep (s : Step) : Bool := s.exercised == .real || s.exercised == .realOnce

/-- Every step has met the real backend. -/
def ready (steps : List Step) : Bool := steps.all realStep

def sound (steps : List Step) (strategies : List (String × Bool)) : Bool :=
  strategies.all fun (_, live) => !live || ready steps

/-- A live strategy means every step has met the real backend. -/
theorem live_needs_every_step (steps : List Step) (strategies : List (String × Bool))
    (h : sound steps strategies = true) (n : String) (hm : (n, true) ∈ strategies) :
    ready steps = true := by
  unfold sound at h
  rw [List.all_eq_true] at h
  have := h _ hm
  simpa using this

end Kagamizo.Readiness
