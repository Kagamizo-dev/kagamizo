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
  /-- What it runs natively, e.g. "aarch64-linux". -/
  platform : String
  deriving DecidableEq, Repr

structure App where
  id : String
  kind : Kind
  command : String
  targets : List String
  /-- What a native app is built for; "" for each target's own. -/
  platform : String
  deriving DecidableEq, Repr

/-- A translator installed on `targets`: runs `src` programs on a `dst` machine. -/
structure Runtime where
  name : String
  src : String
  dst : String
  targets : List String
  deriving DecidableEq, Repr

/-- The platforms one step away from each of `ps` through the runtimes on `t`. -/
def steps (rs : List Runtime) (t : String) (ps : List String) : List String :=
  (rs.filter fun r => r.targets.contains t && ps.contains r.src).map (·.dst)

/-- Whether `q` is reached from `ps` in at most `n` steps on `t`. -/
def reach (rs : List Runtime) (t : String) : Nat → List String → String → Bool
  | 0, ps, q => ps.contains q
  | n + 1, ps, q => ps.contains q || reach rs t n (ps ++ steps rs t ps) q

/-- A program built for `p` runs on target `t` (whose platform is `tp`)
through a chain of the runtimes installed on `t`; no chain is longer than
the number of runtimes. -/
def runs (rs : List Runtime) (t tp p : String) : Bool :=
  reach rs t rs.length [p] tp

/-- A program built for the target's own platform runs there, whatever the
runtimes. -/
theorem own_platform_runs (rs : List Runtime) (t p : String) : runs rs t p p = true := by
  unfold runs
  cases rs.length <;> simp [reach]

def platformOf (ts : List Target) (t : String) : String :=
  match ts.find? (·.name == t) with
  | some x => x.platform
  | none => ""

def unique : List String → Bool
  | [] => true
  | x :: xs => !xs.contains x && unique xs

def isWeb (ts : List Target) (t : String) : Bool :=
  ts.any fun x => x.name == t && x.web

def onPath (images : List (String × List String)) (t cmd : String) : Bool :=
  images.any fun (n, bins) => n == t && bins.contains cmd

/-- One app is sound in the declared targets and images. -/
def appSound (ts : List Target) (rs : List Runtime) (images : List (String × List String)) (a : App) : Bool :=
  !a.targets.isEmpty &&
  a.targets.all (fun t => ts.any (·.name == t)) &&
  a.targets.all (fun t =>
    if isWeb ts t then a.kind != .native
    else a.kind != .native || (onPath images t a.command &&
      runs rs t (platformOf ts t) (if a.platform.isEmpty then platformOf ts t else a.platform)))

/-- Every runtime is installed only on our own images, whose platform is
the one it translates to. -/
def runtimesSound (ts : List Target) (rs : List Runtime) : Bool :=
  unique (rs.map (·.name)) &&
  rs.all fun r => r.targets.all fun t => ts.any fun x => x.name == t && !x.web && x.platform == r.dst

def sound (ts : List Target) (rs : List Runtime) (as : List App) (images : List (String × List String)) : Bool :=
  unique (as.map (·.id)) && unique (ts.map (·.name)) && runtimesSound ts rs && as.all (appSound ts rs images)

/-- On a web target, a sound app is never native. -/
theorem web_never_native (ts : List Target) (rs : List Runtime) (images : List (String × List String)) (a : App)
    (h : appSound ts rs images a = true) (t : String) (ht : t ∈ a.targets) (hw : isWeb ts t = true) :
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
