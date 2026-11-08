/-
The bank's venues (../venues.nix): where it can trade, through which held
account, which classes of instrument, and when each is open, as weekly
sessions in UTC. The owner's criterion (2026-11-08): the bank is
international, with something tradable around the clock. Lean decides:
every class a venue trades has a declared tax treatment; and when the bank
requires it, every hour of the week has a venue open, counting only the
venues it trades or papers on, never the ones merely planned.
-/
namespace Kagamizo.Venues

/-- A weekly session: it opens on `day` (0 Monday .. 6 Sunday) at `start`
minutes past midnight UTC and lasts `minutes`, possibly past midnight. -/
structure Session where
  day : Nat
  start : Nat
  minutes : Nat
  deriving DecidableEq, Repr

structure Venue where
  name : String
  classes : List String
  sessions : List Session
  /-- Traded or papered on (not merely planned). -/
  active : Bool
  deriving DecidableEq, Repr

def week : Nat := 7 * 24 * 60

/-- Whether a session covers the minute `m` of the week (0 = Monday 00:00 UTC). -/
def Session.covers (s : Session) (m : Nat) : Bool :=
  decide ((m + week - (s.day * 24 * 60 + s.start) % week) % week < s.minutes)

def Venue.openAt (v : Venue) (m : Nat) : Bool := v.sessions.any (·.covers m)

/-- The hours of the week (by their first minute) some active venue is open. -/
def coveredHours (vs : List Venue) : Nat :=
  ((List.range 168).filter fun h => vs.any fun v => v.active && v.openAt (h * 60)).length

def treated (treatments : List String) (vs : List Venue) : Bool :=
  vs.all fun v => v.classes.all treatments.contains

def sound (vs : List Venue) (treatments : List String) (aroundTheClock : Bool) : Bool :=
  treated treatments vs && (!aroundTheClock || coveredHours vs == 168)

/-- When the bank requires it, every hour of the week is covered. -/
theorem around_the_clock (vs : List Venue) (treatments : List String)
    (h : sound vs treatments true = true) : coveredHours vs = 168 := by
  unfold sound at h
  simp only [Bool.and_eq_true, Bool.not_true, Bool.false_or, beq_iff_eq] at h
  exact h.2

end Kagamizo.Venues
