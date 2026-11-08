/-
The wallet (modules/bank/wallet.nix): every card is a Proton Pass item of a
catalogued type in a declared vault (the owner's rule, 2026-11-08:
nothing exists that is not typed in a card). What holds today:

- no two cards are the same item (type, vault and title);
- a card's fields are its type's own (catalog/_json/pass-items.json), or
  its app template's;
- a login's second factor, when known, is among what its provider offers.

What is reported until each module moves onto cards (then it becomes a
theorem): the repository's references to Pass items that no card covers,
and logins whose second factor is weaker than their provider offers.
-/
namespace Kagamizo.Wallet

/-- The second factors, strongest first. -/
inductive Factor where
  | passkey
  | securityKey
  | totp
  | email
  | sms
  deriving DecidableEq, Repr

def Factor.rank : Factor → Nat
  | .passkey => 0
  | .securityKey => 1
  | .totp => 2
  | .email => 3
  | .sms => 4

structure Card where
  id : String
  /-- The Pass item type: two items may share a title in one vault when
  their types differ (Public's login and its API credential). -/
  kind : String
  vault : String
  title : String
  fields : List String
  allowed : List String
  factor : Option Factor
  offered : List Factor
  deriving Repr

/-- A reference somewhere in the repository to a Pass item. -/
structure Ref where
  vault : String
  title : String
  from_ : String
  deriving Repr

def same (a b : Card) : Bool := a.kind == b.kind && a.vault == b.vault && a.title == b.title

/-- No two cards are one item. -/
def unique : List Card → Bool
  | [] => true
  | c :: cs => !(cs.any (same c)) && unique cs

/-- A card carries only its type's fields. -/
def typed (c : Card) : Bool := c.fields.all (fun f => c.allowed.contains f)

/-- A known second factor is one its provider offers. -/
def factorOffered (c : Card) : Bool :=
  match c.factor with
  | none => true
  | some f => c.offered.isEmpty || c.offered.contains f

/-- The strongest factor a provider offers. -/
def strongest (fs : List Factor) : Option Factor :=
  fs.foldl (fun acc f => match acc with
    | none => some f
    | some g => if f.rank < g.rank then some f else some g) none

/-- A login using less than its provider's strongest factor: to raise. -/
def weak (c : Card) : Bool :=
  match c.factor, strongest c.offered with
  | some f, some s => s.rank < f.rank
  | _, _ => false

def covered (cards : List Card) (r : Ref) : Bool :=
  cards.any (fun c => c.vault == r.vault && c.title == r.title)

def sound (cards : List Card) : Bool :=
  unique cards && cards.all typed && cards.all factorOffered

/-- In a sound wallet every card is typed: no field outside its type. -/
theorem sound_typed (cards : List Card) (h : sound cards = true) :
    ∀ c ∈ cards, typed c = true := by
  simp only [sound, Bool.and_eq_true, List.all_eq_true] at h
  exact h.1.2

end Kagamizo.Wallet
