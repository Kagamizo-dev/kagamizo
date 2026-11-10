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
  * a path's worst case is the sum of its steps' worst cases, and it is
    within the lead time the path declares;
  * no step of a path uses an excluded channel.
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
  onBreach : Breach
  fallback : Option String
  deriving Repr

structure Path where
  name : String
  steps : List String
  maxLeadMin : Nat
  deriving Repr

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

/-- A step that cannot wait on anyone. -/
def bounded (s : Step) : Bool :=
  decide (0 < s.boundMin) && selfServe s && machine s && read s && checkoutOk s

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
    | some f => bounded f && terminal f && (f.name != s.name)
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

def lead (ss : List Step) (p : Path) : Nat :=
  (p.steps.map (fun n => match find ss n with
    | some s => worst ss s
    | none => 0)).foldl (· + ·) 0

def pathOk (ss : List Step) (excluded : List String) (p : Path) : Bool :=
  !p.steps.isEmpty && p.steps.all (stepOk ss excluded) && decide (lead ss p ≤ p.maxLeadMin)

def sound (ss : List Step) (ps : List Path) (excluded : List String) : Bool :=
  !ps.isEmpty && ps.all (pathOk ss excluded)

/-- A bounded step is reached with no approval and no contract. -/
theorem bounded_is_self_serve (s : Step) (h : bounded s = true) :
    s.access = .keyless ∨ s.access = .open := by
  unfold bounded at h
  simp only [Bool.and_eq_true] at h
  have hs := h.1.1.1.2
  unfold selfServe at hs
  cases ha : s.access <;> simp [ha] at hs ⊢

/-- No person answers inside a bounded step. -/
theorem bounded_waits_on_no_one (s : Step) (h : bounded s = true) :
    s.latency ≠ .human := by
  unfold bounded at h
  simp only [Bool.and_eq_true] at h
  have hm := h.1.1.2
  unfold machine at hm
  intro hl
  simp [hl] at hm

/-- A bounded step has a deadline. -/
theorem bounded_has_deadline (s : Step) (h : bounded s = true) : 0 < s.boundMin := by
  unfold bounded at h
  simp only [Bool.and_eq_true, decide_eq_true_eq] at h
  exact h.1.1.1.1

/-- A bounded browser checkout is one whose store's terms were read. -/
theorem browser_checkout_has_terms (s : Step) (h : bounded s = true)
    (hb : s.checkout = .browser) : s.termsRead = true := by
  unfold bounded at h
  simp only [Bool.and_eq_true] at h
  have hc := h.2
  unfold checkoutOk at hc
  simpa [hb] using hc

/-- Every step of a sound path is bounded. -/
theorem path_steps_bounded (ss : List Step) (excluded : List String) (p : Path)
    (h : pathOk ss excluded p = true) (n : String) (hn : n ∈ p.steps) :
    ∃ s, find ss n = some s ∧ bounded s = true := by
  unfold pathOk at h
  simp only [Bool.and_eq_true] at h
  have hall := h.1.2
  rw [List.all_eq_true] at hall
  have hs := hall n hn
  unfold stepOk at hs
  cases hf : find ss n with
  | none => simp [hf] at hs
  | some s =>
    simp only [hf, Bool.and_eq_true] at hs
    exact ⟨s, rfl, hs.1.1⟩

end Kagamizo.Logistics.Sla
