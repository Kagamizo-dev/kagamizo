/-
The model sheet (../sheets.nix): a model is used by a unit of work only
through a typed sheet that states the model, its licence, the engine and
environment around it, how it is called and what it must achieve. The
sheet is checked before anything runs.

  * hosted: the provider runs the weights; the sheet pins the API, the
    held account that pays, and the host, which must be allowed;
  * weights: we run them; the sheet pins the revision and every file's
    hash, the engine that loads them, and an environment that is offline
    with the engine's telemetry switched off.

A sheet is `usable` only if its licence allows commercial use and its
access waits on no one's approval; it is `live` only with a measured
record inside its targets.
-/
namespace Kagamizo.Agents.Sheets

inductive Access where
  | hosted | weights
  deriving DecidableEq, Repr

/-- How the weights are gated on their hub: not at all, by a click that is
granted at once, or by an author's manual approval (no time bound). -/
inductive Gate where
  | open | automatic | manual
  deriving DecidableEq, Repr

inductive Status where
  | declared | probed | live
  deriving DecidableEq, Repr

structure Record where
  seconds : Nat
  cents : Nat
  deriving Repr

structure Sheet where
  name : String
  access : Access
  commercial : Bool
  gate : Gate
  /-- Hosted: the account is held and the host is on the allowlist. -/
  reachable : Bool
  /-- Weights: revision and every file's hash pinned, and an engine named. -/
  pinned : Bool
  /-- Weights: runs offline with the engine's telemetry off. -/
  sealed : Bool
  maxSeconds : Nat
  maxCents : Nat
  record : Option Record
  status : Status
  deriving Repr

def environmentOk (s : Sheet) : Bool :=
  match s.access with
  | .hosted => s.reachable
  | .weights => s.pinned && s.sealed

def approvalFree (s : Sheet) : Bool :=
  match s.gate with
  | .manual => false
  | _ => true

/-- A sheet a unit of work may call. -/
def usable (s : Sheet) : Bool :=
  s.commercial && approvalFree s && environmentOk s &&
    decide (0 < s.maxSeconds) && decide (0 < s.maxCents)

def within (s : Sheet) (r : Record) : Bool :=
  decide (r.seconds ≤ s.maxSeconds) && decide (r.cents ≤ s.maxCents)

/-- A live sheet has a measured record inside its targets; a sheet that is
not live claims nothing. -/
def perfOk (s : Sheet) : Bool :=
  match s.status, s.record with
  | .live, some r => within s r
  | .live, none => false
  | _, some r => within s r
  | _, none => true

def sound (ss : List Sheet) : Bool :=
  ss.all (fun s => usable s && perfOk s)

/-- A usable model's licence allows commercial use. -/
theorem usable_is_commercial (s : Sheet) (h : usable s = true) : s.commercial = true := by
  unfold usable at h
  simp only [Bool.and_eq_true] at h
  exact h.1.1.1.1

/-- A usable model waits on no author's approval. -/
theorem usable_waits_on_no_approval (s : Sheet) (h : usable s = true) : s.gate ≠ .manual := by
  unfold usable at h
  simp only [Bool.and_eq_true] at h
  have ha := h.1.1.1.2
  unfold approvalFree at ha
  intro hg
  simp [hg] at ha

/-- Weights we run are pinned and sealed. -/
theorem weights_are_pinned_and_sealed (s : Sheet) (h : usable s = true)
    (hw : s.access = .weights) : s.pinned = true ∧ s.sealed = true := by
  unfold usable at h
  simp only [Bool.and_eq_true] at h
  have he := h.1.1.2
  unfold environmentOk at he
  simpa [hw] using he

/-- A live model was measured, and inside its time and cost targets. -/
theorem live_meets_its_targets (s : Sheet) (h : perfOk s = true) (hl : s.status = .live) :
    ∃ r, s.record = some r ∧ r.seconds ≤ s.maxSeconds ∧ r.cents ≤ s.maxCents := by
  unfold perfOk at h
  cases hr : s.record with
  | none => simp [hl, hr] at h
  | some r =>
    simp only [hl, hr] at h
    unfold within at h
    simp only [Bool.and_eq_true, decide_eq_true_eq] at h
    exact ⟨r, rfl, h.1, h.2⟩

end Kagamizo.Agents.Sheets
