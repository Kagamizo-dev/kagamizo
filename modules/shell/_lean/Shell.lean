/-
The shell's declarations (../shell.nix): targets, apps, and each NixOS
image's PATH, rendered after this file. Lean decides the shell is sound:
app ids are unique, every app ships on a declared target, the web target
holds only web and built-in apps (a browser cannot run a native program),
and every native app's command is on the PATH of every image it ships in.
-/
namespace Kagamizo.Shell

inductive Kind where
  | native | web | builtin | module
  deriving DecidableEq, Repr

structure Target where
  name : String
  /-- A browser or a phone: it runs the web target, never a native program. -/
  web : Bool
  deriving DecidableEq, Repr

structure App where
  id : String
  kind : Kind
  command : String
  targets : List String
  deriving DecidableEq, Repr

def unique : List String → Bool
  | [] => true
  | x :: xs => !xs.contains x && unique xs

def isWeb (ts : List Target) (t : String) : Bool :=
  ts.any fun x => x.name == t && x.web

def onPath (images : List (String × List String)) (t cmd : String) : Bool :=
  images.any fun (n, bins) => n == t && bins.contains cmd

/-- One app is sound in the declared targets and images. -/
def appSound (ts : List Target) (images : List (String × List String)) (a : App) : Bool :=
  !a.targets.isEmpty &&
  a.targets.all (fun t => ts.any (·.name == t)) &&
  a.targets.all (fun t =>
    if isWeb ts t then a.kind != .native
    else a.kind != .native || onPath images t a.command)

def sound (ts : List Target) (as : List App) (images : List (String × List String)) : Bool :=
  unique (as.map (·.id)) && unique (ts.map (·.name)) && as.all (appSound ts images)

/-- On a web target, a sound app is never native. -/
theorem web_never_native (ts : List Target) (images : List (String × List String)) (a : App)
    (h : appSound ts images a = true) (t : String) (ht : t ∈ a.targets) (hw : isWeb ts t = true) :
    a.kind ≠ .native := by
  unfold appSound at h
  simp only [Bool.and_eq_true, List.all_eq_true] at h
  have := h.2 t ht
  simp [hw] at this
  exact this

/-- The library covers the repository: every module is part of the base
or registers at least one app. -/
def covered (modules base appModules : List String) : Bool :=
  modules.all fun m => base.contains m || appModules.contains m

/-- In a covered library, no module is invisible: each is a Settings row
or a card. -/
theorem covered_visible (modules base appModules : List String)
    (h : covered modules base appModules = true) (m : String) (hm : m ∈ modules) :
    m ∈ base ∨ m ∈ appModules := by
  unfold covered at h
  rw [List.all_eq_true] at h
  have := h m hm
  simp only [Bool.or_eq_true, List.contains_iff_mem] at this
  exact this

end Kagamizo.Shell
