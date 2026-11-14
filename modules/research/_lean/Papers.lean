/-
The redaction rule of the research papers (modules/research/papers.nix).
A paper's inputs are facts: a named field, its value, and whether it may
be published. The renderer's only input is `render facts`, the public
ones; the theorems are what that guarantees: nothing private reaches a
paper, nothing public is lost, and when the public flags agree with an
allowlist (which ../papers.nix renders and Lean decides for every declared
paper), every rendered field is on it. The denylist scan of the rendered
text is the check's second half, for what a value may carry.
-/
namespace Kagamizo.Papers

/-- One input to a paper. -/
structure Fact where
  field : String
  value : String
  /-- Declared public by the allowlist; everything else is private. -/
  published : Bool
  deriving DecidableEq, Repr

/-- The renderer's only input: the public facts. -/
def render (facts : List Fact) : List Fact := facts.filter (·.published)

/-- Everything a rendered paper holds was declared public. -/
theorem render_only_public (facts : List Fact) : ∀ f ∈ render facts, f.published = true := by
  intro f h
  exact (List.mem_filter.mp h).2

/-- A private fact is never rendered. -/
theorem private_never_rendered (facts : List Fact) (f : Fact) (h : f.published = false) :
    f ∉ render facts := by
  intro hm
  have := render_only_public facts f hm
  rw [h] at this
  exact Bool.false_ne_true this

/-- Nothing public is lost: the paper is exactly the public inputs. -/
theorem render_complete (facts : List Fact) (f : Fact) (hf : f ∈ facts) (hp : f.published = true) :
    f ∈ render facts :=
  List.mem_filter.mpr ⟨hf, hp⟩

/-- Rendering adds nothing: a rendered fact was an input. -/
theorem render_sub (facts : List Fact) (f : Fact) (h : f ∈ render facts) : f ∈ facts :=
  (List.mem_filter.mp h).1

/-- When every fact is public exactly if its field is allowed, every
rendered field is allowed. -/
theorem render_fields_allowed (allowed : List String) (facts : List Fact)
    (h : facts.all (fun f => f.published == allowed.contains f.field) = true) :
    ∀ f ∈ render facts, f.field ∈ allowed := by
  intro f hf
  have hp := render_only_public facts f hf
  have ha := List.all_eq_true.mp h f (render_sub facts f hf)
  rw [hp] at ha
  exact List.contains_iff_mem.mp (beq_iff_eq.mp ha).symm

/-- A field no fact declares public is absent from the rendering. -/
theorem hidden_field_absent (facts : List Fact) (name : String)
    (h : facts.all (fun f => f.field != name || !f.published) = true) :
    ∀ f ∈ render facts, f.field ≠ name := by
  intro f hf heq
  have hp := render_only_public facts f hf
  have hx := List.all_eq_true.mp h f (render_sub facts f hf)
  rw [hp, heq] at hx
  simp at hx

end Kagamizo.Papers
