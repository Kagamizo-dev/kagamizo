/-
Logistics (../logistics.nix): from a specification to a thing in the
owner's hands, anywhere, with reliability first and price last (the
owner's rule, 2026-11-08: "we don't care at all, even if it's a
drastically better price; the biggest thing is reliability").

Four parts, each decided here over what ../logistics.nix renders:

  * channels: every marketplace, maker, carrier, courier and holding
    point, typed by what software may do with it. A channel whose terms
    forbid automation is never automated, whatever its declaration says
    it could do (`noScraping`).
  * hubs: places where things land, chosen by airport; every region the
    owner named has one, and there is exactly one home.
  * the outfit: the garments that carry the kit (../../kit), so that
    every slot holding a device is provided by a garment whose pockets
    hold it, every garment survives the wash, and nothing is a pack.
  * routes: a delivery is a chain of legs (source, line, hold, courier),
    each with a reliability in basis points and a worst-case duration.
    `best` picks, among the routes that meet the deadline and the
    reliability floor, the most reliable one; price only breaks a tie.
    The Rust CLI (../_src) runs the same rule over live quotes.
-/
namespace Kagamizo.Logistics

/-! ## Channels -/

/-- How software reaches one operation of a channel: keyless (no account
at all), open (self-serve
key), gated (an approval or an account first), partner (a contract), or
none (by hand only). -/
inductive Access where
  | keyless | open | gated | partner | none
  deriving DecidableEq, Repr

/-- What a channel's own terms say about automated access. -/
inductive Terms where
  | allowed | apiOnly | forbidden | unknown
  deriving DecidableEq, Repr

structure Op where
  name : String
  access : Access
  deriving DecidableEq, Repr

structure Channel where
  name : String
  kind : String
  regions : List String
  terms : Terms
  ops : List Op
  deriving DecidableEq, Repr

def Op.automated (o : Op) : Bool := o.access != .none

/-- Where terms forbid automation, every operation is by hand. -/
def noScraping (c : Channel) : Bool :=
  c.terms != .forbidden || c.ops.all (!·.automated)

def unique : List String → Bool
  | [] => true
  | x :: xs => !xs.contains x && unique xs

def channelsSound (cs : List Channel) : Bool :=
  unique (cs.map (·.name)) && cs.all noScraping && cs.all (!·.regions.isEmpty)

/-- A channel that passes `noScraping` and forbids automation offers no
automated operation at all. -/
theorem forbidden_is_manual (c : Channel) (h : noScraping c = true)
    (hf : c.terms = .forbidden) : ∀ o ∈ c.ops, o.automated = false := by
  unfold noScraping at h
  simp only [hf, bne_self_eq_false, Bool.false_or, List.all_eq_true,
    Bool.not_eq_eq_eq_not, Bool.not_true] at h
  exact h

/-! ## Hubs -/

structure Hub where
  name : String
  region : String
  airports : List String
  home : Bool
  deriving DecidableEq, Repr

def hubsSound (regions : List String) (hs : List Hub) : Bool :=
  unique (hs.map (·.name)) &&
  regions.all (fun r => hs.any (·.region == r)) &&
  (hs.filter (·.home)).length == 1 &&
  hs.all (!·.airports.isEmpty)

/-! ## The outfit -/

structure Slot where
  name : String
  volumeMl : Nat
  /-- Whether a device sits in it today or is proposed for it. -/
  used : Bool
  deriving DecidableEq, Repr

structure Garment where
  name : String
  kind : String
  /-- The kit slots its pockets are, each with the pocket's volume. -/
  provides : List (String × Nat)
  massG : Nat
  washable : Bool
  deriving DecidableEq, Repr

/-- Kinds a carried thing may never be: the owner never wears a pack. -/
def forbiddenKinds : List String := ["backpack", "bag", "case"]

def pocketFor (gs : List Garment) (s : String) : Nat :=
  gs.foldl (fun a g => a + (g.provides.filter (·.1 == s)).foldl (fun b p => b + p.2) 0) 0

/-- Every used slot, except those worn on the body itself, is a pocket of
some garment that holds the slot's volume; each slot is provided once;
every garment washes; none is a pack; the whole outfit stays under its
mass limit. -/
def outfitSound (slots : List Slot) (worn : List String) (gs : List Garment) (maxMassG : Nat) : Bool :=
  unique (gs.map (·.name)) &&
  slots.all (fun s => !s.used || worn.contains s.name || decide (s.volumeMl ≤ pocketFor gs s.name)) &&
  unique (gs.flatMap (·.provides.map (·.1))) &&
  gs.all (fun g => g.provides.all (fun p => slots.any (·.name == p.1))) &&
  gs.all (·.washable) &&
  gs.all (fun g => !forbiddenKinds.contains g.kind) &&
  decide (gs.foldl (fun a g => a + g.massG) 0 ≤ maxMassG)

/-! ## Routes -/

/-- One leg: a reliability in basis points (10000 is certain) and its
worst-case duration in hours. -/
structure Leg where
  channel : String
  bp : Nat
  hours : Nat
  deriving DecidableEq, Repr

structure Route where
  name : String
  legs : List Leg
  costCents : Nat
  deriving DecidableEq, Repr

/-- The chance every leg holds, in basis points, rounded down: legs are
treated as independent, which is the optimistic case; ../_src states the
same and the paper says why. -/
def Route.rel (r : Route) : Nat :=
  r.legs.foldl (fun a l => a * l.bp / 10000) 10000

def Route.hours (r : Route) : Nat :=
  r.legs.foldl (fun a l => a + l.hours) 0

/-- Keep `a` unless `b` is more reliable, or as reliable and cheaper. -/
def pick (a b : Route) : Route :=
  if a.rel < b.rel ∨ (b.rel = a.rel ∧ b.costCents < a.costCents) then b else a

def best : List Route → Option Route
  | [] => none
  | r :: rs => some (rs.foldl pick r)

def eligible (floorBp deadline : Nat) (r : Route) : Bool :=
  decide (floorBp ≤ r.rel) && decide (r.hours ≤ deadline)

def choose (floorBp deadline : Nat) (rs : List Route) : Option Route :=
  best (rs.filter (eligible floorBp deadline))

theorem pick_ge (a b : Route) : a.rel ≤ (pick a b).rel ∧ b.rel ≤ (pick a b).rel := by
  unfold pick
  split <;> rename_i h <;> omega

theorem pick_cases (a b : Route) : pick a b = a ∨ pick a b = b := by
  unfold pick
  split
  · exact Or.inr rfl
  · exact Or.inl rfl

theorem foldl_ge (rs : List Route) (init : Route) :
    init.rel ≤ (rs.foldl pick init).rel ∧ ∀ r ∈ rs, r.rel ≤ (rs.foldl pick init).rel := by
  induction rs generalizing init with
  | nil => exact ⟨Nat.le_refl _, fun _ h => nomatch h⟩
  | cons x xs ih =>
    have h1 := pick_ge init x
    have h2 := ih (pick init x)
    refine ⟨Nat.le_trans h1.1 h2.1, ?_⟩
    intro r hr
    cases hr with
    | head => exact Nat.le_trans h1.2 h2.1
    | tail _ hr => exact h2.2 r hr

theorem foldl_keeps (P : Route → Prop) (rs : List Route) (init : Route)
    (hi : P init) (hr : ∀ r ∈ rs, P r) : P (rs.foldl pick init) := by
  induction rs generalizing init with
  | nil => exact hi
  | cons x xs ih =>
    apply ih (pick init x)
    · cases pick_cases init x with
      | inl h => rw [h]; exact hi
      | inr h => rw [h]; exact hr x (List.Mem.head _)
    · intro r h; exact hr r (List.Mem.tail _ h)

/-- The chosen route is at least as reliable as every candidate. -/
theorem best_most_reliable (rs : List Route) (b : Route) (h : best rs = some b) :
    ∀ r ∈ rs, r.rel ≤ b.rel := by
  cases rs with
  | nil => exact nomatch h
  | cons x xs =>
    simp only [best, Option.some.injEq] at h
    subst h
    intro r hr
    have := foldl_ge xs x
    cases hr with
    | head => exact this.1
    | tail _ hr => exact this.2 r hr

/-- The chosen route meets the deadline and the floor, and no route that
also meets them is more reliable. Price never outranks reliability. -/
theorem choose_sound (floorBp deadline : Nat) (rs : List Route) (b : Route)
    (h : choose floorBp deadline rs = some b) :
    eligible floorBp deadline b = true ∧
    ∀ r ∈ rs, eligible floorBp deadline r = true → r.rel ≤ b.rel := by
  unfold choose at h
  constructor
  · cases hl : rs.filter (eligible floorBp deadline) with
    | nil => rw [hl] at h; exact nomatch h
    | cons x xs =>
      rw [hl] at h
      simp only [best, Option.some.injEq] at h
      subst h
      have hall : ∀ r ∈ x :: xs, eligible floorBp deadline r = true := by
        intro r hr
        rw [← hl] at hr
        exact (List.mem_filter.mp hr).2
      exact foldl_keeps (fun r => eligible floorBp deadline r = true) xs x
        (hall x (List.Mem.head _)) (fun r hr => hall r (List.Mem.tail _ hr))
  · intro r hr he
    exact best_most_reliable _ b h r (List.mem_filter.mpr ⟨hr, he⟩)

/-! ## Should-cost and quotes

A thing's should-cost is its bill of materials, its machine time and its
labour, each line a quantity in thousandths of its unit times a rate in
cents per unit. A line without a sourced rate is unpriced, and a thing
with an unpriced line has no should-cost: nothing is negotiated against a
guess. A supplier's quote is acceptable only within a declared premium of
the should-cost and only with an inspection plan, so quality is part of
the price, not a later hope. -/

structure Line where
  name : String
  qtyMilli : Nat
  rateCents : Option Nat
  deriving DecidableEq, Repr

def Line.cents (l : Line) : Nat :=
  match l.rateCents with
  | some r => l.qtyMilli * r / 1000
  | none => 0

def total : List Line → Nat
  | [] => 0
  | l :: ls => l.cents + total ls

def shouldCost (ls : List Line) : Option Nat :=
  if ls.all (·.rateCents.isSome) then some (total ls) else none

structure Quote where
  supplier : String
  cents : Nat
  /-- An inspection plan agreed before production (ISO 2859-1 sampling). -/
  inspection : Bool
  deriving DecidableEq, Repr

def acceptable (shouldCents premiumPct : Nat) (q : Quote) : Bool :=
  q.inspection && decide (q.cents * 100 ≤ shouldCents * (100 + premiumPct))

/-- More lines never cost less. -/
theorem total_append_ge (ls ms : List Line) : total ls ≤ total (ls ++ ms) := by
  induction ls with
  | nil => exact Nat.zero_le _
  | cons l ls ih => simp only [List.cons_append, total]; omega

/-- A thing with an unpriced line has no should-cost. -/
theorem unpriced_has_no_cost (ls : List Line) (l : Line) (hl : l ∈ ls)
    (hn : l.rateCents = none) : shouldCost ls = none := by
  unfold shouldCost
  have : ls.all (·.rateCents.isSome) = false := by
    rw [Bool.eq_false_iff]
    intro h
    have := List.all_eq_true.mp h l hl
    simp [hn] at this
  simp [this]

/-- An accepted quote has an inspection plan and is within the premium. -/
theorem accepted_is_bounded (s p : Nat) (q : Quote) (h : acceptable s p q = true) :
    q.inspection = true ∧ q.cents * 100 ≤ s * (100 + p) := by
  unfold acceptable at h
  simp only [Bool.and_eq_true, decide_eq_true_eq] at h
  exact h

def sound (cs : List Channel) (regions : List String) (hs : List Hub)
    (slots : List Slot) (worn : List String) (gs : List Garment) (maxMassG : Nat) : Bool :=
  channelsSound cs && hubsSound regions hs && outfitSound slots worn gs maxMassG

end Kagamizo.Logistics
