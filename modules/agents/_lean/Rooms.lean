/-
The teams' rooms (../rooms.nix): talking to a team is talking in its room.
Every team is its own identity on the homeserver and has one room, which
holds the owner and that team and no one else, so what a team is told and
what it answers is never mixed with another's.

  * every team has exactly one room, and every room is a team's;
  * no two rooms share an alias;
  * a room's members are the owner and its own team, nothing more.
-/
namespace Kagamizo.Rooms

structure Room where
  team : String
  alias : String
  members : List String
  deriving Repr

def roomOk (owner : String) (r : Room) : Bool :=
  r.members == [owner, r.team] && r.team != owner

def sound (owner : String) (teams : List String) (rooms : List Room) : Bool :=
  teams.all (fun t => (rooms.filter fun r => r.team == t).length == 1) &&
    rooms.all (fun r => teams.contains r.team && roomOk owner r) &&
    rooms.all (fun r => (rooms.filter fun s => s.alias == r.alias).length == 1)

/-- A room holds the owner and its own team, and no one else. -/
theorem room_holds_the_owner_and_its_team (owner : String) (teams : List String)
    (rooms : List Room) (h : sound owner teams rooms = true) (r : Room) (hr : r ∈ rooms) :
    r.members = [owner, r.team] := by
  unfold sound at h
  simp only [Bool.and_eq_true] at h
  have hall := h.1.2
  rw [List.all_eq_true] at hall
  have hk := hall r hr
  simp only [Bool.and_eq_true] at hk
  have ho := hk.2
  unfold roomOk at ho
  simp only [Bool.and_eq_true] at ho
  simpa using ho.1

/-- Every team has exactly one room. -/
theorem team_has_one_room (owner : String) (teams : List String) (rooms : List Room)
    (h : sound owner teams rooms = true) (t : String) (ht : t ∈ teams) :
    (rooms.filter fun r => r.team == t).length = 1 := by
  unfold sound at h
  simp only [Bool.and_eq_true] at h
  have hall := h.1.1
  rw [List.all_eq_true] at hall
  simpa using hall t ht

end Kagamizo.Rooms
