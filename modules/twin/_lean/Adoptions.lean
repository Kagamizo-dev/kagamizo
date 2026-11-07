/-
What the twin adopts (modules/twin/adoptions.nix): open projects pinned by
commit, run as their own process, or only studied. ../adoptions.nix renders
the declarations after this file; Lean decides the rules that keep the twin
open, Rust and tested.
-/
namespace Kagamizo.Adoptions

structure Adoption where
  name : String
  role : String
  license : String
  language : String
  use : String
  tests : Nat
  deriving DecidableEq, Repr

def permissive : List String :=
  ["mit", "apache-2", "mit-or-apache-2", "bsd", "mpl-2", "cc0", "cc-by-4"]

def copyleft : List String := ["gpl-3", "agpl-3", "lgpl-3"]

/-- The parts that run the twin, as opposed to references and assets. -/
def runtimeRoles : List String := ["server", "bot", "map-render", "browser-view", "map-format"]

/-- Pinned code is permissive; copyleft code only runs as its own process;
anything else (a closed licence) is only ever studied. -/
def Adoption.licensed (a : Adoption) : Bool :=
  match a.use with
  | "pin" => permissive.contains a.license
  | "process" => permissive.contains a.license || copyleft.contains a.license
  | _ => true

/-- What we run is Rust. -/
def Adoption.rust (a : Adoption) : Bool :=
  a.use == "study" || !runtimeRoles.contains a.role || a.language == "rust"

/-- Nothing is trusted until its tests are ported. -/
def Adoption.tested (a : Adoption) : Bool :=
  a.use == "study" || a.tests > 0

def Adoption.sound (a : Adoption) : Bool := a.licensed && a.rust && a.tested

/-- A closed licence can never be pinned. -/
theorem closed_never_pinned (a : Adoption) (h : a.licensed = true)
    (hl : a.license = "all-rights-reserved") : a.use ≠ "pin" := by
  intro hu
  simp [Adoption.licensed, hu, hl, permissive] at h

end Kagamizo.Adoptions
