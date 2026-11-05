/-
Attenuable agent capabilities, proven never to escalate. An agent's
*authority* is exactly its governance grants (../../governance: pairs of an
account it may touch and an effect, read or write — spending, destroying
and signing in are never an agent's). ../default.nix renders them. A
capability is a set of such pairs; minting gives the authority, attenuating
keeps a subset, and a check passes only for a pair in the capability.

Lean decides, over every agent, that minting and any attenuation stay
within the authority, so a delegated token — however far it is passed and
narrowed — can never permit what the agent's grant does not. (The biscuit
token, biscuit-auth 6.0.0, is the wire format that carries this capability
with public-key offline attenuation; this is the policy it encodes.)
-/
namespace Kagamizo.Delegation

structure Cap where
  account : String
  effect : String
  deriving DecidableEq, Repr

/-- A capability is within another when every pair it allows is allowed by
the other: attenuation only narrows. -/
def within (sub authority : List Cap) : Bool :=
  sub.all (authority.contains ·)

/-- Attenuate an authority to a requested subset, or reject (none) if the
request reaches past it. -/
def attenuate (authority request : List Cap) : Option (List Cap) :=
  if within request authority then some request else none

def permits (cap : List Cap) (c : Cap) : Bool := cap.contains c

/-- `within` is transitive: a narrowing of a narrowing is a narrowing of the
whole, so passing a token down a chain never widens it. -/
theorem within_trans (a b c : List Cap) (hab : within a b = true) (hbc : within b c = true) :
    within a c = true := by
  simp only [within, List.all_eq_true] at *
  intro x hx
  have hxb := hab x hx
  simp only [List.contains_eq_mem, decide_eq_true_eq] at hxb ⊢
  have := hbc x
  simp only [List.contains_eq_mem, decide_eq_true_eq] at this
  exact this (by simpa using hxb)

/-- Anything an attenuation permits, the authority permits: no escalation. -/
theorem attenuate_no_escalation (authority request narrowed : List Cap)
    (h : attenuate authority request = some narrowed) (c : Cap)
    (hc : permits narrowed c = true) : permits authority c = true := by
  unfold attenuate at h
  split at h
  · next hw =>
    cases h
    simp only [within, List.all_eq_true] at hw
    have hmem : c ∈ authority := by
      have := hw c (by simpa [permits, List.contains_eq_mem] using hc)
      simpa [List.contains_eq_mem] using this
    simpa [permits, List.contains_eq_mem] using hmem
  · contradiction

-- What the rule refuses, on stand-ins.
private def auth : List Cap := [{ account := "northwest-jingzo", effect := "read" }]
/-- Requesting an effect the authority lacks is rejected. -/
example : attenuate auth [{ account := "northwest-jingzo", effect := "write" }] = none := by decide
/-- Requesting another account is rejected. -/
example : attenuate auth [{ account := "mercury-jingzo", effect := "read" }] = none := by decide
/-- A genuine subset is admitted. -/
example : attenuate auth [{ account := "northwest-jingzo", effect := "read" }] = some [{ account := "northwest-jingzo", effect := "read" }] := by decide

end Kagamizo.Delegation
