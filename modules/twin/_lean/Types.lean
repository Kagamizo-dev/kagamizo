/-
The digital twin world (modules/twin): every representation is typed with its
kind, what it represents, its district, its sprite shape, and its recipes.
../world.nix concatenates this file with the rendered facts and the
all-theorems, then Lean decides that every perf-target module has exactly one
building, every agent has exactly one character, every district is declared,
every sprite is 16x16 over the palette, and every recipe names a governance
action that exists.

NOTE: This file leaves the namespace open; world.nix closes it after the
rendered facts and theorems.
-/
namespace Kagamizo.Twin

/-- What kind of thing a representation is. -/
inductive Kind
  | building
  | item
  | block
  | character
  deriving DecidableEq, Repr

/-- What the thing stands for: exactly one of these is non-empty. -/
structure Ref where
  mod : Option String
  account : Option String
  team : Option String
  asset : Option String
  deriving DecidableEq, Repr

/-- A sprite is 16 rows of 16 chars over the palette (represented here as a
list of 16 strings, each of length 16). -/
structure Sprite where
  rows : List String
  deriving DecidableEq, Repr

/-- A district in the world. -/
structure District where
  label : String
  order : Nat
  deriving DecidableEq, Repr

/-- A recipe wrapping a governance action. -/
structure Recipe where
  action : String
  inputs : List String
  outputs : List String
  deriving DecidableEq, Repr

/-- One representation in the world. -/
structure Representation where
  name : String
  kind : Kind
  of : Ref
  sprite : Option Sprite
  place : String
  recipes : List Recipe
  status : String
  deriving DecidableEq, Repr

/-- Every sprite is null or a valid 16×16 grid. -/
def Representation.spriteValid (r : Representation) : Bool :=
  match r.sprite with
  | none => true
  | some s => s.rows.length = 16 ∧ s.rows.all (fun row => row.length = 16)

/-- Every representation's place is a known district. -/
def Representation.placeDeclared (r : Representation)
    (ds : List (String × District)) : Bool :=
  ds.any (fun (n, _) => n = r.place)

/-- Every recipe's action is a declared governance action. -/
def Representation.recipesKnown (r : Representation)
    (actions : List String) : Bool :=
  r.recipes.all fun rec => actions.contains rec.action

/-- Every module with a perf target has exactly one building. -/
def moduleHasBuilding (reps : List Representation)
    (modName : String) : Bool :=
  (reps.filter fun r =>
    r.kind = Kind.building ∧ r.of.mod = some modName).length = 1

/-- Every agent has exactly one character. -/
def agentHasCharacter (reps : List Representation)
    (agentName : String) : Bool :=
  (reps.filter fun r =>
    r.kind = Kind.character ∧ r.of.team = some agentName).length = 1