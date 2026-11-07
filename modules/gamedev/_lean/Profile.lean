/-
The game-development profile (modules/gamedev/default.nix): engines and
toolchains, each with the licence nixpkgs states for it, and one declared
testing-and-shipping platform, Steam. The rule: every entry of the profile
is open source unless it is under the platform (`gamedev.steam`), and the
platform's entries are in the profile only while `gamedev.steam.enable` is.
../default.nix renders the declarations after this file and Lean decides
them.
-/
namespace Kagamizo.GameDev

/-- One entry of the profile: an engine, a toolchain or a platform tool.
`license` is the SPDX id nixpkgs states (or its short name where nixpkgs has
no SPDX id, as for Steam's unfree licence); `proprietary` is nixpkgs' own
verdict (`!meta.license.free`); `platform` says the entry is declared under
`gamedev.steam`, the one testing-and-shipping platform. -/
structure Tool where
  name : String
  license : String
  proprietary : Bool
  platform : Bool
  deriving DecidableEq, Repr

def Tool.openSource (t : Tool) : Bool := !t.proprietary

/-- The rule, for one entry: open source, or under the platform. -/
def Tool.allowed (t : Tool) : Bool := t.openSource || t.platform

/-- The profile: the open-source entries always, the platform's entries
only when it is enabled. -/
def profile (base steam : List Tool) (enabled : Bool) : List Tool :=
  base ++ (if enabled then steam else [])

/-- Disabled, the profile is its open-source base and nothing else. -/
theorem profile_disabled (base steam : List Tool) :
    profile base steam false = base := by
  simp [profile]

/-- Enabled, the profile is the base followed by the platform's entries:
enabling Steam adds exactly the Steam entries. -/
theorem profile_enabled (base steam : List Tool) :
    profile base steam true = base ++ steam := by
  simp [profile]

/-- Whatever enabling adds was declared under the platform: an entry of the
enabled profile that is not in the base is one of the Steam entries. -/
theorem enabled_adds_only_steam (base steam : List Tool) (t : Tool)
    (h : t ∈ profile base steam true) (hb : t ∉ base) : t ∈ steam := by
  rw [profile_enabled] at h
  rcases List.mem_append.mp h with h' | h'
  · exact absurd h' hb
  · exact h'

/-- And enabling removes nothing: every base entry stays. -/
theorem enabled_keeps_base (base steam : List Tool) (t : Tool) (h : t ∈ base) :
    t ∈ profile base steam true := by
  rw [profile_enabled]
  exact List.mem_append_left _ h

/-- When the rendered facts decide the base open source and the platform's
entries all under the platform, every entry of the profile, enabled or
not, keeps the rule: proprietary only under the platform. -/
theorem rule (base steam : List Tool) (enabled : Bool)
    (hb : base.all Tool.openSource = true) (hs : steam.all (·.platform) = true) :
    ∀ t ∈ profile base steam enabled, t.proprietary = true → t.platform = true := by
  intro t ht hp
  unfold profile at ht
  rcases List.mem_append.mp ht with h | h
  · have := List.all_eq_true.mp hb t h
    simp [Tool.openSource, hp] at this
  · cases enabled with
    | false => simp at h
    | true =>
      simp at h
      exact List.all_eq_true.mp hs t h

/-- Conversely, nothing outside the platform is proprietary: the base and
the platform are the only places an entry lives, and the base is open. -/
theorem proprietary_is_platform (base steam : List Tool) (enabled : Bool)
    (hb : base.all Tool.openSource = true) (hs : steam.all (·.platform) = true) :
    (profile base steam enabled).all Tool.allowed = true := by
  apply List.all_eq_true.mpr
  intro t ht
  unfold Tool.allowed Tool.openSource
  cases hp : t.proprietary with
  | false => rfl
  | true => simp [rule base steam enabled hb hs t ht hp]

end Kagamizo.GameDev
