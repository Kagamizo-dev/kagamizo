/-
The carried kit (../kit.nix): a solo researcher's devices, worn in the
pockets and sleeves of their clothes. Each item sits in one slot of the
clothing, provides capabilities, and draws power from its own battery or
from the kit's shared bank. A proposal is not a product: it is the worst
case a product must meet (at most its mass, volume and draw, at least its
battery), so a loadout proved with proposals holds for any product that
meets them. ../kit.nix renders the declarations after this file and Lean
decides them.
-/
namespace Kagamizo.Kit

structure Slot where
  name : String
  volumeMl : Nat
  massG : Nat
  deriving DecidableEq, Repr

/-- `bank`: the item draws from the shared power bank; otherwise from its
own battery. Power in milliwatts, energy in milliwatt-hours. -/
structure Item where
  name : String
  slot : String
  massG : Nat
  volumeMl : Nat
  powerMw : Nat
  batteryMwh : Nat
  bank : Bool
  provides : List String
  owned : Bool
  runsSoftware : Bool
  deriving DecidableEq, Repr

/-- What a loadout must carry, and for how many hours away from a socket. -/
structure Requirement where
  capabilities : List String
  hours : Nat
  deriving DecidableEq, Repr

def sum (f : Item → Nat) (xs : List Item) : Nat := xs.foldl (fun a x => a + f x) 0

/-- Every slot holds no more than its volume and mass, and every item sits
in a declared slot. -/
def fits (slots : List Slot) (items : List Item) : Bool :=
  items.all (fun i => slots.any (·.name == i.slot)) &&
  slots.all fun s =>
    let here := items.filter (·.slot == s.name)
    decide (sum (·.massG) here ≤ s.massG) && decide (sum (·.volumeMl) here ≤ s.volumeMl)

def covers (caps : List String) (items : List Item) : Bool :=
  caps.all fun c => items.any (·.provides.contains c)

/-- Every item lasts the hours: one on its own battery from that battery;
the items on the bank from the bank's items together (the items that
provide `power`). -/
def lasts (hours : Nat) (items : List Item) : Bool :=
  let banked := items.filter (·.bank)
  let bankMwh := sum (·.batteryMwh) (items.filter (·.provides.contains "power"))
  items.all (fun i => i.bank || i.provides.contains "power" || decide (hours * i.powerMw ≤ i.batteryMwh)) &&
  decide (hours * sum (·.powerMw) banked ≤ bankMwh)

/-- Every item that runs software is a target of the shell. -/
def targeted (targets : List String) (items : List Item) : Bool :=
  items.all fun i => !i.runsSoftware || targets.contains i.name

def meets (slots : List Slot) (targets : List String) (r : Requirement) (items : List Item) : Bool :=
  fits slots items && covers r.capabilities items && lasts r.hours items && targeted targets items

/-- What can run today: an item on the bank only once a bank is carried. -/
def runnable (items : List Item) : List Item :=
  let hasBank := items.any (·.provides.contains "power")
  items.filter fun i => !i.bank || hasBank

def unique : List String → Bool
  | [] => true
  | x :: xs => !xs.contains x && unique xs

/-- The kit is sound: names unique, what is owned and can run meets today's
requirement, and what is owned with the proposals meets the target. -/
def sound (slots : List Slot) (targets : List String) (now target : Requirement) (items : List Item) : Bool :=
  unique (items.map (·.name)) && unique (slots.map (·.name)) &&
  meets slots targets now (runnable (items.filter (·.owned))) &&
  meets slots targets target items

/-- Carrying more never loses a capability: a covered requirement stays
covered whatever is added. -/
theorem covers_append (caps : List String) (xs ys : List Item)
    (h : covers caps xs = true) : covers caps (xs ++ ys) = true := by
  unfold covers at *
  simp only [List.all_eq_true, List.any_append, Bool.or_eq_true] at *
  intro c hc
  exact Or.inl (h c hc)

/-- A capability no item provides cannot be covered: a requirement fails,
naming what is missing, until something provides it. -/
theorem uncovered (c : String) (caps : List String) (items : List Item)
    (hc : c ∈ caps) (hn : ∀ i ∈ items, c ∉ i.provides) : covers caps items = false := by
  unfold covers
  rw [Bool.eq_false_iff]
  intro h
  simp only [List.all_eq_true, List.any_eq_true] at h
  obtain ⟨i, hi, hp⟩ := h c hc
  exact hn i hi (List.contains_iff_mem.mp hp)

end Kagamizo.Kit
