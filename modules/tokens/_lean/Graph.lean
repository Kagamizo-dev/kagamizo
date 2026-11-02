/-
The credential graph: every credential the repository mints, derived from
another credential, down to a root the owner approves (a sign-in).

A node names its parent (none for a root) and its scope, the set of things
it can do in its provider's own vocabulary (Cloudflare's OAuth scopes,
Proton Pass's vault roles, ...). ../default.nix renders every declared
credential as a node, roots first and each child after its parent.

The rule, checked for the rendered graph by `decide`:

  * every parent is declared, and earlier in the list (so the graph is a
    forest: no cycle, every credential traces back to a root);
  * a child's scope is contained in its parent's: deriving a credential
    can only narrow what it can do, never widen it;
  * a root is issued by a human step (the owner's approval), a child by
    automation.

The theorems below state what that guarantees for any graph that keeps
the rule; the facts file appended by ../default.nix proves the repository's
own graph keeps it.
-/
namespace Kagamizo.Tokens

inductive Issuer where
  | human
  | automation
  deriving DecidableEq, Repr

structure Node where
  id : String
  parent : Option String
  issuer : Issuer
  scope : List String
  deriving DecidableEq, Repr

def subset (a b : List String) : Bool := a.all (fun x => b.contains x)

/-- The node's parent, looked up among the nodes before it. -/
def parentIn (before : List Node) (n : Node) : Option Node :=
  n.parent.bind (fun p => before.find? (fun m => m.id == p))

/-- One node keeps the rule, given the nodes before it. -/
def keeps (before : List Node) (n : Node) : Bool :=
  match n.parent with
  | none => n.issuer == .human
  | some _ =>
    match parentIn before n with
    | none => false
    | some p => n.issuer == .automation && subset n.scope p.scope

/-- The whole list keeps the rule, each node against those before it. -/
def wellFormed : List Node → Bool
  | [] => true
  | ns => (List.range ns.length).all (fun i =>
      match ns[i]? with
      | some n => keeps (ns.take i) n
      | none => true)

theorem subset_trans (a b c : List String) (hab : subset a b = true) (hbc : subset b c = true) :
    subset a c = true := by
  simp only [subset, List.all_eq_true, List.contains_iff_mem] at *
  intro x hx
  exact hbc x (by simpa using hab x hx)

/-- A child is never broader than its parent. -/
theorem keeps_narrows (before : List Node) (n p : Node)
    (hk : keeps before n = true) (hp : parentIn before n = some p) :
    subset n.scope p.scope = true := by
  unfold keeps at hk
  cases h : n.parent with
  | none => simp [parentIn, h] at hp
  | some _ =>
    rw [h] at hk
    simp only [hp, Bool.and_eq_true] at hk
    exact hk.2

/-- A child is minted by automation, never by hand. -/
theorem keeps_child_automated (before : List Node) (n p : Node)
    (hk : keeps before n = true) (hp : parentIn before n = some p) :
    n.issuer = .automation := by
  unfold keeps at hk
  cases h : n.parent with
  | none => simp [parentIn, h] at hp
  | some _ =>
    rw [h] at hk
    simp only [hp, Bool.and_eq_true, beq_iff_eq] at hk
    exact hk.1

/-- A root is the owner's approval. -/
theorem keeps_root_human (before : List Node) (n : Node)
    (hk : keeps before n = true) (h : n.parent = none) : n.issuer = .human := by
  unfold keeps at hk
  rw [h] at hk
  simpa using hk

end Kagamizo.Tokens
