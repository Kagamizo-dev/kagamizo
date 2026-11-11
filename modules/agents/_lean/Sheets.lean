/-
The model sheet (../sheets.nix): a unit of work calls a model only through
a typed sheet. We run no weights ourselves (the owner, 2026-11-11): every
model is a provider's, routed through the one held account, and what we
build is the harness around its modality: what goes in, what must come
out, how long it may take and what it may cost.

A sheet is `usable` only if its licence allows commercial use, the account
that pays is held and its host allowed, a harness exists for what it
returns, and it takes only the inputs that harness sends. It is `live`
only with a measured record inside its targets.
-/
namespace Kagamizo.Agents.Sheets

/-- What a harness sends to a model. -/
inductive Input where
  | text | image
  deriving DecidableEq, Repr

/-- What a model returns. -/
inductive Output where
  | image | svg | mesh | text
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
  inputs : List Input
  output : Output
  commercial : Bool
  /-- The account that pays is held and the host is on the allowlist. -/
  reachable : Bool
  maxSeconds : Nat
  maxCents : Nat
  record : Option Record
  status : Status
  deriving Repr

/-- The outputs a harness exists for (../_picture holds images and
drawings to their format). -/
def harnessed (o : Output) : Bool :=
  match o with
  | .image | .svg => true
  | _ => false

/-- A sheet a unit of work may call. -/
def usable (s : Sheet) : Bool :=
  s.commercial && s.reachable && harnessed s.output && !s.inputs.isEmpty &&
    decide (0 < s.maxSeconds) && decide (0 < s.maxCents)

def within (s : Sheet) (r : Record) : Bool :=
  decide (r.seconds ≤ s.maxSeconds) && decide (r.cents ≤ s.maxCents)

/-- A live sheet has a measured record inside its targets, and any record
a sheet carries is inside them. -/
def perfOk (s : Sheet) : Bool :=
  match s.status, s.record with
  | .live, none => false
  | _, some r => within s r
  | _, none => true

def sound (ss : List Sheet) : Bool :=
  ss.all (fun s => usable s && perfOk s)

/-- A usable model's licence allows commercial use. -/
theorem usable_is_commercial (s : Sheet) (h : usable s = true) : s.commercial = true := by
  unfold usable at h
  simp only [Bool.and_eq_true] at h
  exact h.1.1.1.1.1

/-- A usable model returns something a harness holds to its format. -/
theorem usable_has_a_harness (s : Sheet) (h : usable s = true) :
    s.output = .image ∨ s.output = .svg := by
  unfold usable at h
  simp only [Bool.and_eq_true] at h
  have hh := h.1.1.1.2
  unfold harnessed at hh
  cases ho : s.output <;> simp [ho] at hh ⊢

/-- A usable model is paid for by a held account on an allowed host. -/
theorem usable_is_reachable (s : Sheet) (h : usable s = true) : s.reachable = true := by
  unfold usable at h
  simp only [Bool.and_eq_true] at h
  exact h.1.1.1.1.2

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
