/-
The digital twin of the owner's phone (modules/android/default.nix): an
emulated device whose state is its base image plus its declared settings
plus its declared apps, and nothing else. The base is a hash, every app is
pinned by a hash, and every setting names one of Android's three settings
namespaces. ../default.nix renders the declarations after this file and
Lean decides them.
-/
namespace Kagamizo.Twin

/-- A base image: what the device boots before anything declared is
applied. `kind` is `aosp` (the SDK's emulator image) or `grapheneos` (a
future build job); `image` is the SDK package id; `sha1` is the archive's
hash as the SDK repository states it. -/
structure Base where
  kind : String
  image : String
  sha1 : String
  deriving DecidableEq, Repr

/-- Android's settings namespaces, as `adb shell settings put` takes them. -/
inductive Namespace
  | global
  | system
  | secure
  deriving DecidableEq, Repr

def Namespace.parse? : String → Option Namespace
  | "global" => some .global
  | "system" => some .system
  | "secure" => some .secure
  | _ => none

/-- One `settings put <ns> <key> <value>`. The namespace is kept as the
string the declaration gave, so that Lean, not Nix, decides it is one of
the three. -/
structure Setting where
  ns : String
  key : String
  value : String
  deriving DecidableEq, Repr

def Setting.typed (s : Setting) : Bool := (Namespace.parse? s.ns).isSome

/-- An app, pinned: its APK's sha256. -/
structure App where
  name : String
  sha256 : String
  deriving DecidableEq, Repr

def isHex (c : Char) : Bool := c.isDigit || ('a' ≤ c && c ≤ 'f')

def hexOfLength (n : Nat) (s : String) : Bool :=
  s.toList.length == n && s.toList.all isHex

def App.pinned (a : App) : Bool := hexOfLength 64 a.sha256
def Base.pinned (b : Base) : Bool := hexOfLength 40 b.sha1

def Base.known (b : Base) : Bool := b.kind == "aosp" || b.kind == "grapheneos"

/-- A declared device. -/
structure Device where
  name : String
  base : Base
  settings : List Setting
  apps : List App
  deriving DecidableEq, Repr

/-- The rule: a device's state is a function of (base, settings, apps). -/
def Device.state (d : Device) : Base × List Setting × List App :=
  (d.base, d.settings, d.apps)

/-- Two devices declared alike are in the same state: nothing outside the
declaration reaches the state. -/
theorem state_of_declaration (d e : Device)
    (hb : d.base = e.base) (hs : d.settings = e.settings) (ha : d.apps = e.apps) :
    d.state = e.state := by
  simp [Device.state, hb, hs, ha]

/-- Putting a setting. -/
def Device.put (d : Device) (s : Setting) : Device :=
  { d with settings := s :: d.settings }

/-- Installing an app. -/
def Device.install (d : Device) (a : App) : Device :=
  { d with apps := a :: d.apps }

/-- Changing a setting never changes the base. -/
theorem put_keeps_base (d : Device) (s : Setting) : (d.put s).base = d.base := rfl

/-- Adding an app never changes the base. -/
theorem install_keeps_base (d : Device) (a : App) : (d.install a).base = d.base := rfl

/-- Nor do any number of them. -/
theorem puts_keep_base (d : Device) (ss : List Setting) :
    (ss.foldl Device.put d).base = d.base := by
  induction ss generalizing d with
  | nil => rfl
  | cons s ss ih => simpa [List.foldl, put_keeps_base] using ih (d.put s)

theorem installs_keep_base (d : Device) (as : List App) :
    (as.foldl Device.install d).base = d.base := by
  induction as generalizing d with
  | nil => rfl
  | cons a as ih => simpa [List.foldl, install_keeps_base] using ih (d.install a)

def Device.appsPinned (d : Device) : Bool := d.apps.all App.pinned
def Device.settingsTyped (d : Device) : Bool := d.settings.all Setting.typed

/-- When the rendered facts decide every app pinned, each app's hash is 64
hex characters. -/
theorem pinned_each (ds : List Device) (h : ds.all Device.appsPinned = true) :
    ∀ d ∈ ds, ∀ a ∈ d.apps, a.sha256.toList.length = 64 ∧ a.sha256.toList.all isHex = true := by
  intro d hd a ha
  have hd' := List.all_eq_true.mp h d hd
  have ha' := List.all_eq_true.mp hd' a ha
  simp only [App.pinned, hexOfLength, Bool.and_eq_true, beq_iff_eq] at ha'
  exact ha'

/-- When the rendered facts decide every setting typed, each setting's
namespace parses to one of the three. -/
theorem typed_each (ds : List Device) (h : ds.all Device.settingsTyped = true) :
    ∀ d ∈ ds, ∀ s ∈ d.settings, ∃ n : Namespace, Namespace.parse? s.ns = some n := by
  intro d hd s hs
  have hd' := List.all_eq_true.mp h d hd
  have hs' := List.all_eq_true.mp hd' s hs
  simp only [Setting.typed, Option.isSome_iff_exists] at hs'
  exact hs'

end Kagamizo.Twin
