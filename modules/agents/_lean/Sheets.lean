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

What a call costs is not estimated (the owner's rule, 2026-11-17): every
provider's price for a sheet's model is pinned from OpenRouter's own list
(../_json/media-prices.json), with the unit it bills in. Where the unit
bounds a call by itself (an image, or a megapixel at the most megapixels
the sheet asks for), the dearest pinned price is proved within the
sheet's cap (`priced_within_cap`). Where it bills by output token, the
price alone does not bound a call; such sheets are counted, and the count
may only fall (`unbounded_within_baseline`). For those the harness's own
refusal of a result over the cap is the control.
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

/-- What a provider bills an image in. -/
inductive Unit where
  | image | megapixel | token
  deriving DecidableEq, Repr

/-- One provider's pinned price: millionths of a dollar per unit. -/
structure Price where
  provider : String
  unit : Unit
  microUsd : Nat
  deriving Repr

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
  /-- Every provider's pinned price for its model. -/
  prices : List Price
  /-- The most it asks for, in tenths of a megapixel. -/
  tenthsMegapixels : Nat
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

/-- The most one image can cost at a pinned price, in millionths of a
dollar, where the unit bounds it. -/
def worst (s : Sheet) (p : Price) : Option Nat :=
  match p.unit with
  | .image => some p.microUsd
  | .megapixel => some (p.microUsd * s.tenthsMegapixels / 10)
  | .token => none

/-- Every pinned price bounds a call, and within the cap. -/
def bounded (s : Sheet) : Bool :=
  s.prices.all (fun p =>
    match worst s p with
    | some w => decide (w ≤ s.maxCents * 10000)
    | none => false)

/-- A sheet's model is priced by at least one provider. -/
def priced (s : Sheet) : Bool :=
  !s.prices.isEmpty

def unbounded (ss : List Sheet) : Nat :=
  (ss.filter (fun s => !bounded s)).length

def sound (ss : List Sheet) (baseline : Nat) : Bool :=
  ss.all (fun s => usable s && perfOk s && priced s) && decide (unbounded ss ≤ baseline)

/-- Whatever provider serves a bounded sheet, one image costs no more
than the sheet's cap, at the pinned prices. -/
theorem priced_within_cap (s : Sheet) (h : bounded s = true) (p : Price) (hp : p ∈ s.prices) :
    ∃ w, worst s p = some w ∧ w ≤ s.maxCents * 10000 := by
  unfold bounded at h
  rw [List.all_eq_true] at h
  have hw := h p hp
  cases hc : worst s p with
  | none => simp [hc] at hw
  | some w =>
    simp only [hc, decide_eq_true_eq] at hw
    exact ⟨w, rfl, hw⟩

/-- The sheets no pinned price bounds are within the baseline. -/
theorem unbounded_within_baseline (ss : List Sheet) (baseline : Nat)
    (h : sound ss baseline = true) : unbounded ss ≤ baseline := by
  unfold sound at h
  simp only [Bool.and_eq_true, decide_eq_true_eq] at h
  exact h.2

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
