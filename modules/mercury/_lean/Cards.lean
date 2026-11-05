/-
The declared Mercury cards (mercury.cards) against the committed discovery
(_json/cards.json, written by `cards discover`). ../discovery.nix renders
both and Lean decides: every declared card on a discovered account is
live, at its declared limit and period, and every live `kagamizo/*` card is
declared. An account not yet discovered says nothing about its cards.
-/
namespace Kagamizo.Mercury

structure Declared where
  name : String
  nickname : String
  account : String
  limitCents : Nat
  period : String
  merchantLock : Option String
  deriving Repr

structure Live where
  nickname : Option String
  account : String
  status : String
  limitCents : Option Nat
  period : Option String
  merchantLock : Option String
  deriving Repr

structure Discovery where
  /-- The accounts whose cards were listed. -/
  accounts : List String
  cards : List Live
  deriving Repr

/-- Not ended: cancelled and expired cards are gone, the rest are live. -/
def Live.isLive (l : Live) : Bool := l.status != "cancelled" && l.status != "expired"

/-- A live card that is the declared one, at its limit and period. -/
def Live.fulfils (l : Live) (d : Declared) : Bool :=
  l.isLive && l.nickname == some d.nickname && l.account == d.account &&
    l.limitCents == some d.limitCents && l.period == some d.period

def Discovery.declaredLive (x : Discovery) (ds : List Declared) : Bool :=
  ds.all fun d => !x.accounts.contains d.account || x.cards.any (·.fulfils d)

def Live.ours (l : Live) : Bool :=
  l.isLive && (l.nickname.map (·.startsWith "kagamizo/")).getD false

def Discovery.liveDeclared (x : Discovery) (ds : List Declared) : Bool :=
  x.cards.all fun l => !l.ours || ds.any fun d => d.nickname == l.nickname.getD "" && d.account == l.account

/-- A fulfilled declaration is backed by a card that is live. -/
theorem fulfils_live (l : Live) (d : Declared) (h : l.fulfils d = true) : l.isLive = true := by
  simp [Live.fulfils, Bool.and_eq_true] at h
  exact h.1.1.1.1

/-- A cancelled card fulfils nothing. -/
theorem cancelled_fulfils_nothing (l : Live) (d : Declared) (h : l.status = "cancelled") :
    l.fulfils d = false := by
  simp [Live.fulfils, Live.isLive, h]

end Kagamizo.Mercury
