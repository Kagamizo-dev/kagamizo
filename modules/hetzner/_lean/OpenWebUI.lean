/-
Open WebUI's bounds on jingzo-host (modules/hetzner/open-webui.nix): the
pinned version's switches, read from its source, each decided; the ones
that run code on the host, override the declarations or reach out never
on; and every variable the host sets one that version reads or a declared
library variable. ../open-webui.nix renders the facts after this file.
-/
namespace Kagamizo.OpenWebUI

/-- Every switch in the catalog has a decision. -/
def allDecided (catalog decided : List String) : Bool :=
  catalog.all decided.contains

/-- None of the forbidden switches is on. -/
def noneForbidden (on mustBeOff : List String) : Bool :=
  mustBeOff.all fun s => !on.contains s

/-- Every variable set is known to the version (or a declared library). -/
def allKnown (known set : List String) : Bool :=
  set.all known.contains

def bounds (catalog decided on mustBeOff known set : List String) : Bool :=
  allDecided catalog decided && noneForbidden on mustBeOff && allKnown known set

/-- A forbidden switch that holds the bound is not on. -/
theorem forbidden_off (on mustBeOff : List String) (s : String)
    (h : noneForbidden on mustBeOff = true) (hs : s ∈ mustBeOff) : s ∉ on := by
  unfold noneForbidden at h
  have := List.all_eq_true.mp h s hs
  simpa using this

end Kagamizo.OpenWebUI
