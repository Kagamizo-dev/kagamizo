/-
A strategy's stage (modules/trading/stages.nix): research, backtest,
paper, live. Each promotion is declared with its evidence: a recorded
backtest to reach paper; paper days that held (enough of them, no loss,
the drawdown within bound, from `trade paper-settle`'s ledger) and the
owner's dated decision to reach live. `wellStaged` is the rule ../stages.nix renders
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
  /-- The settled paper trades held: P&L not below zero and the drawdown
  within 20% (../stages.nix, from the ledger). -/
  paperHeld : Bool
  /-- The owner's dated decision to go live. -/
  decided : Bool
  deriving DecidableEq, Repr

/-- The paper days a strategy needs before it may go live. -/
def paperDaysNeeded : Nat := 5

def wellStaged (s : Strategy) : Bool :=
  (s.stage.rank < Stage.paper.rank || s.backtested)
  && (s.stage ≠ .live || (s.paperDays ≥ paperDaysNeeded && s.paperHeld && s.decided))

/-- A live strategy was backtested, papered long enough, held on paper,
and decided. -/
theorem live_has_evidence (s : Strategy) (h : wellStaged s = true) (hl : s.stage = .live) :
    s.backtested = true ∧ s.paperDays ≥ paperDaysNeeded ∧ s.paperHeld = true ∧ s.decided = true := by
  unfold wellStaged at h
  rw [hl] at h
  simp [Stage.rank] at h
  exact ⟨h.1, h.2.1.1, h.2.1.2, h.2.2⟩

/-- Paper days alone never make a strategy live: a loss on paper keeps it
off, however many days it ran. -/
theorem paper_loss_blocks_live (s : Strategy) (hl : s.stage = .live) (hp : s.paperHeld = false) :
    wellStaged s = false := by
  unfold wellStaged
  simp [hl, hp, Stage.rank]

/-- A paper strategy was backtested. -/
theorem paper_was_backtested (s : Strategy) (h : wellStaged s = true) (hp : s.stage = .paper) :
    s.backtested = true := by
  unfold wellStaged at h
  rw [hp] at h
  simp [Stage.rank] at h
  exact h

end Kagamizo.Stages
