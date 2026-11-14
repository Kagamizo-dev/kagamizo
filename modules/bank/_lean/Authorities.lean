/-
The bank's authorities and its providers' terms (../authorities.nix).
Lean decides three rules: no interface the bank relies on needs a phone
number as its second factor (the owner's rule: no SMS-only providers);
every clause of a provider's terms cites a page; and every revenue source
at Public lands on a person's account, because Public's Individual Trader
API Agreement covers only accounts opened in the developer's own name.
-/
namespace Kagamizo.Authorities

structure Interface where
  authority : String
  name : String
  sms : Bool
  relied : Bool
  deriving DecidableEq, Repr

structure Revenue where
  name : String
  provider : String
  entityKind : String
  deriving DecidableEq, Repr

/-- Public's terms reach a source only when it is on a person's account. -/
def publicOk (r : Revenue) : Bool :=
  r.provider != "public" || r.entityKind == "person"

def sound (interfaces : List Interface) (clauses : List (String × String)) (revenue : List Revenue) : Bool :=
  interfaces.all (fun i => !(i.relied && i.sms)) &&
  clauses.all (fun c => c.2.startsWith "https://") &&
  revenue.all publicOk

/-- In a sound bank, revenue at Public is on a person's account. -/
theorem public_is_personal (interfaces : List Interface) (clauses : List (String × String))
    (revenue : List Revenue) (h : sound interfaces clauses revenue = true)
    (r : Revenue) (hr : r ∈ revenue) (hp : r.provider = "public") : r.entityKind = "person" := by
  unfold sound at h
  simp only [Bool.and_eq_true, List.all_eq_true] at h
  have := h.2 r hr
  unfold publicOk at this
  simp [hp] at this
  exact this

end Kagamizo.Authorities
