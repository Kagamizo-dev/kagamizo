/-
No unbounded step (../sla.nix; the owner's rule, 2026-11-10): the chain
from a design to parts in hand is a closed loop in which nothing waits on a
person, an approval or a reply. Makers rarely promise a bound, so the bound
is ours: every step has a deadline in minutes and an action taken when it
passes, and a step is on a path only if software reaches it by itself.

  * a step is `bounded` when its deadline is positive, its channel is
    keyless or self-serve (never an approval or a contract), no person
    answers inside it, the provider's own page was read for it, and a
    browser checkout is used only where the store's terms were read;
  * a breach either retries once, fails with the step named, or moves to a
    fallback step that is itself bounded and ends there (`breachOk`);
  * a path is a sequence of stages; the steps of a stage run side by side,
    so a stage takes as long as its slowest step and a path as long as its
    stages together;
  * the desired outcome is stated first and proved of every path: its worst
    case is within the one target lead time (`lead_within_target`);
  * a path is not tied to one country: every step has a jurisdiction and a
    path a destination, and goods made elsewhere reach it only through a
    step that clears that border and is itself bounded
    (`goods_cross_only_cleared`). Which jurisdictions to make in is then an
    optimisation over the rules of each;
  * no step of a path uses an excluded channel;
  * no assumption is left bare: a deadline of ours is never shorter than
    the provider's own figure (`deadline_covers_stated`), a fallback is
    another channel than the one that failed (`fallback_is_another_channel`),
    and every deadline no provider states rests on a declared assumption
    with its backing (a dataset, a paper, a theorem, a simulation or a
    measurement). Those not yet backed are counted, and the count may only
    fall.
-/
namespace Kagamizo.Logistics.Sla

/-- How software reaches a channel (as ./Logistics.lean's `Access`). -/
inductive Access where
  | keyless | open | gated | partner | none
  deriving DecidableEq, Repr

/-- Who answers inside the step: the channel at once, a file it publishes
on its own cadence, or a person. -/
inductive Latency where
  | instant | published | human
  deriving DecidableEq, Repr

/-- How an order is placed: an API, an agent checkout protocol the store
publishes, a governed browser, or nothing is ordered (a read). -/
inductive Checkout where
  | read | api | protocol | browser
  deriving DecidableEq, Repr

/-- What the provider's claims rest on. -/
inductive Evidence where
  | page | snippet | secondary
  deriving DecidableEq, Repr

/-- What happens when the deadline passes. Never "wait". -/
inductive Breach where
  | retry | reroute | fail
  deriving DecidableEq, Repr

structure Step where
  name : String
  channel : String
  access : Access
  latency : Latency
  checkout : Checkout
  evidence : Evidence
  /-- The store's terms on automated use were read whole. -/
  termsRead : Bool
  boundMin : Nat
  /-- The provider's own figure for the step, where it states one. -/
  statedMin : Option Nat
  /-- The deadline is the provider's, or rests on a backed assumption. -/
  backed : Bool
  onBreach : Breach
  fallback : Option String
  /-- Where the step happens (ISO 3166-1 alpha-2). -/
  jurisdiction : String
  /-- Physical goods leave this step. -/
  goods : Bool
  /-- The border this step clears goods across, from and to. -/
  clears : Option (String × String)
  deriving Repr

structure Path where
  name : String
  /-- Where the finished goods are delivered. -/
  destination : String
  /-- In order; the steps of one stage run side by side. -/
  stages : List (List String)
  deriving Repr

def Path.steps (p : Path) : List String :=
  p.stages.foldr (· ++ ·) []

def selfServe (s : Step) : Bool :=
  match s.access with
  | .keyless | .open => true
  | _ => false

def machine (s : Step) : Bool :=
  match s.latency with
  | .human => false
  | _ => true

def read (s : Step) : Bool :=
  match s.evidence with
  | .page => true
  | _ => false

def checkoutOk (s : Step) : Bool :=
  match s.checkout with
  | .browser => s.termsRead
  | _ => true

/-- Our deadline is never shorter than the provider's own figure. -/
def covers (s : Step) : Bool :=
  match s.statedMin with
  | some m => decide (m ≤ s.boundMin)
  | none => true

/-- A step that cannot wait on anyone. -/
def bounded (s : Step) : Bool :=
  decide (0 < s.boundMin) && selfServe s && machine s && read s && checkoutOk s && covers s

def find (ss : List Step) (n : String) : Option Step :=
  ss.find? (fun s => s.name == n)

def terminal (s : Step) : Bool :=
  match s.onBreach with
  | .reroute => false
  | _ => true

/-- A breach ends: it retries once, fails, or lands on another bounded step
that does not reroute again. -/
def breachOk (ss : List Step) (s : Step) : Bool :=
  match s.onBreach with
  | .retry | .fail => true
  | .reroute =>
    match s.fallback.bind (find ss) with
    | some f => bounded f && terminal f && (f.name != s.name) && (f.channel != s.channel)
    | none => false

/-- The longest a step takes by itself: a retry runs it once more. -/
def own (s : Step) : Nat :=
  match s.onBreach with
  | .retry => 2 * s.boundMin
  | _ => s.boundMin

/-- The longest a step can take, its breach included. -/
def worst (ss : List Step) (s : Step) : Nat :=
  match s.onBreach with
  | .reroute =>
    match s.fallback.bind (find ss) with
    | some f => s.boundMin + own f
    | none => s.boundMin
  | _ => own s

def stepOk (ss : List Step) (excluded : List String) (n : String) : Bool :=
  match find ss n with
  | some s => bounded s && breachOk ss s && !(excluded.contains s.channel)
  | none => false

def stepWorst (ss : List Step) (n : String) : Nat :=
  match find ss n with
  | some s => worst ss s
  | none => 0

/-- A stage takes as long as its slowest step. -/
def stageWorst (ss : List Step) (stage : List String) : Nat :=
  (stage.map (stepWorst ss)).foldl max 0

def lead (ss : List Step) (p : Path) : Nat :=
  (p.stages.map (stageWorst ss)).foldl (· + ·) 0

/-- Goods made outside the destination pass a step of the path that clears
that border. -/
def cleared (ss : List Step) (p : Path) (s : Step) : Bool :=
  !s.goods || s.jurisdiction == p.destination ||
    p.steps.any (fun n =>
      match find ss n with
      | some c => c.clears == some (s.jurisdiction, p.destination)
      | none => false)

def crossingsOk (ss : List Step) (p : Path) : Bool :=
  p.steps.all (fun n =>
    match find ss n with
    | some s => cleared ss p s
    | none => false)

def pathOk (ss : List Step) (excluded : List String) (target : Nat) (p : Path) : Bool :=
  !p.steps.isEmpty && p.steps.all (stepOk ss excluded) && crossingsOk ss p &&
    decide (lead ss p ≤ target)

/-- The steps of a path, their fallbacks included, whose deadline rests on
nothing yet. -/
def unbacked (ss : List Step) (p : Path) : Nat :=
  ((p.steps ++ p.steps.filterMap (fun n => (find ss n).bind (·.fallback))).filter (fun n =>
    match find ss n with
    | some s => !s.backed
    | none => true)).length

def unbackedAll (ss : List Step) (ps : List Path) : Nat :=
  (ps.map (unbacked ss)).foldl (· + ·) 0

/-- Every path is sound and within the one target lead time, and the
assumptions not yet backed are within the baseline. -/
def sound (ss : List Step) (ps : List Path) (excluded : List String) (target : Nat)
    (baseline : Nat) : Bool :=
  !ps.isEmpty && ps.all (pathOk ss excluded target) && decide (unbackedAll ss ps ≤ baseline)

/-- The outcome wanted, stated first: no sound path takes longer than the
target, its breaches included. -/
theorem lead_within_target (ss : List Step) (ps : List Path) (excluded : List String)
    (target baseline : Nat) (h : sound ss ps excluded target baseline = true) (p : Path)
    (hp : p ∈ ps) : lead ss p ≤ target := by
  unfold sound at h
  simp only [Bool.and_eq_true] at h
  have hall := h.1.2
  rw [List.all_eq_true] at hall
  have hp' := hall p hp
  unfold pathOk at hp'
  simp only [Bool.and_eq_true, decide_eq_true_eq] at hp'
  exact hp'.2

/-- Goods never cross a border on a sound path without a step that clears
it. -/
theorem goods_cross_only_cleared (ss : List Step) (excluded : List String) (target : Nat)
    (p : Path) (h : pathOk ss excluded target p = true) (n : String) (hn : n ∈ p.steps)
    (s : Step) (hf : find ss n = some s) : cleared ss p s = true := by
  unfold pathOk at h
  simp only [Bool.and_eq_true] at h
  have hc := h.1.2
  unfold crossingsOk at hc
  rw [List.all_eq_true] at hc
  have hs := hc n hn
  simpa [hf] using hs

/-- A bounded step is reached with no approval and no contract. -/
theorem bounded_is_self_serve (s : Step) (h : bounded s = true) :
    s.access = .keyless ∨ s.access = .open := by
  unfold bounded at h
  simp only [Bool.and_eq_true] at h
  have hs := h.1.1.1.1.2
  unfold selfServe at hs
  cases ha : s.access <;> simp [ha] at hs ⊢

/-- No person answers inside a bounded step. -/
theorem bounded_waits_on_no_one (s : Step) (h : bounded s = true) :
    s.latency ≠ .human := by
  unfold bounded at h
  simp only [Bool.and_eq_true] at h
  have hm := h.1.1.1.2
  unfold machine at hm
  intro hl
  simp [hl] at hm

/-- A bounded step has a deadline. -/
theorem bounded_has_deadline (s : Step) (h : bounded s = true) : 0 < s.boundMin := by
  unfold bounded at h
  simp only [Bool.and_eq_true, decide_eq_true_eq] at h
  exact h.1.1.1.1.1

/-- A bounded browser checkout is one whose store's terms were read. -/
theorem browser_checkout_has_terms (s : Step) (h : bounded s = true)
    (hb : s.checkout = .browser) : s.termsRead = true := by
  unfold bounded at h
  simp only [Bool.and_eq_true] at h
  have hc := h.1.2
  unfold checkoutOk at hc
  simpa [hb] using hc

/-- A deadline of ours is never shorter than what the provider states. -/
theorem deadline_covers_stated (s : Step) (h : bounded s = true) (m : Nat)
    (hm : s.statedMin = some m) : m ≤ s.boundMin := by
  unfold bounded at h
  simp only [Bool.and_eq_true] at h
  have hc := h.2
  unfold covers at hc
  simpa [hm] using hc

/-- A reroute lands on another channel than the one that failed. -/
theorem fallback_is_another_channel (ss : List Step) (s : Step)
    (h : breachOk ss s = true) (hr : s.onBreach = .reroute) :
    ∃ f, s.fallback.bind (find ss) = some f ∧ f.channel ≠ s.channel := by
  unfold breachOk at h
  simp only [hr] at h
  cases hf : s.fallback.bind (find ss) with
  | none => simp [hf] at h
  | some f =>
    simp only [hf, Bool.and_eq_true] at h
    exact ⟨f, rfl, by simpa using h.2⟩

/-- The assumptions not yet backed are within the baseline. -/
theorem unbacked_within_baseline (ss : List Step) (ps : List Path) (excluded : List String)
    (target baseline : Nat) (h : sound ss ps excluded target baseline = true) :
    unbackedAll ss ps ≤ baseline := by
  unfold sound at h
  simp only [Bool.and_eq_true, decide_eq_true_eq] at h
  exact h.2

/-- Every step of a sound path is bounded. -/
theorem path_steps_bounded (ss : List Step) (excluded : List String) (target : Nat)
    (p : Path) (h : pathOk ss excluded target p = true) (n : String) (hn : n ∈ p.steps) :
    ∃ s, find ss n = some s ∧ bounded s = true := by
  unfold pathOk at h
  simp only [Bool.and_eq_true] at h
  have hall := h.1.1.2
  rw [List.all_eq_true] at hall
  have hs := hall n hn
  unfold stepOk at hs
  cases hf : find ss n with
  | none => simp [hf] at hs
  | some s =>
    simp only [hf, Bool.and_eq_true] at hs
    exact ⟨s, rfl, hs.1.1⟩

end Kagamizo.Logistics.Sla
