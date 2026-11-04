/-
A strategy's stage (modules/trading/stages.nix): research, backtest,
paper, live. Each promotion is declared with its evidence: a recorded
backtest to reach paper, recorded paper days and the owner's dated
decision to reach live. `wellStaged` is the rule ../stages.nix renders
every declared strategy against; the theorems are what it guarantees:
nothing is live without every piece of evidence, so `trade place` never
sees an unproven strategy.
-/
namespace Kagamizo.Stages

inductive Stage where
  | research
  | backtest
  | paper
  | live
  deriving DecidableEq, Repr

def Stage.rank : Stage → Nat
  | .research => 0
  | .backtest => 1
  | .paper => 2
  | .live => 3

structure Strategy where
  name : String
  stage : Stage
  /-- A backtest is recorded (grid, alpha, drawdown) and met the thresholds. -/
  backtested : Bool
  /-- Recorded paper days with preflight-accepted proposals. -/
  paperDays : Nat
  /-- The owner's dated decision to go live. -/
  decided : Bool
  deriving DecidableEq, Repr

/-- The paper days a strategy needs before it may go live. -/
def paperDaysNeeded : Nat := 5

def wellStaged (s : Strategy) : Bool :=
  (s.stage.rank < Stage.paper.rank || s.backtested)
  && (s.stage ≠ .live || (s.paperDays ≥ paperDaysNeeded && s.decided))

/-- A live strategy was backtested, papered long enough, and decided. -/
theorem live_has_evidence (s : Strategy) (h : wellStaged s = true) (hl : s.stage = .live) :
    s.backtested = true ∧ s.paperDays ≥ paperDaysNeeded ∧ s.decided = true := by
  unfold wellStaged at h
  rw [hl] at h
  simp [Stage.rank] at h
  exact ⟨h.1, h.2.1, h.2.2⟩

/-- A paper strategy was backtested. -/
theorem paper_was_backtested (s : Strategy) (h : wellStaged s = true) (hp : s.stage = .paper) :
    s.backtested = true := by
  unfold wellStaged at h
  rw [hp] at h
  simp [Stage.rank] at h
  exact h

end Kagamizo.Stages
