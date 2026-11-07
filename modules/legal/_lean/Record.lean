/-
The legal record of every entity (modules/legal/options.nix): what a record
must hold for the entity's standing. ../options.nix renders the declared
records after this file; Lean decides that each is complete for its status.

A person needs nothing. A planned company states its purpose, its
organization (owners whose shares sum to 100, managers exactly when
manager-managed) and the state it is formed in: in the repository while
it is the plan, or in its formation item once it is on file (the item
holds the filing number, state and date in Proton Pass, since the
repository is public). An active company adds that formation item, its
EIN item, its registered agent and the formation document it holds.
A record complete for `active` is complete for `planned`: nothing a plan
needs is lost by forming.
-/
namespace Kagamizo.Legal

inductive Status where
  | natural
  | planned
  | forming
  | active
  | dissolved
  deriving DecidableEq, Repr

inductive Management where
  | memberManaged
  | managerManaged
  deriving DecidableEq, Repr

structure Member where
  entity : String
  percent : Nat
  deriving DecidableEq, Repr

inductive DocumentKind where
  | formation
  | operatingAgreement
  | einLetter
  | agentAcceptance
  | annualReport
  | other
  deriving DecidableEq, Repr

structure Document where
  kind : DocumentKind
  title : String
  issued : Option String
  deriving DecidableEq, Repr

structure Record where
  entity : String
  status : Status
  purpose : Option String
  management : Option Management
  members : List Member
  managers : List String
  /-- The state of formation, when it is public (the plan). -/
  state : Option String
  /-- The Proton Pass item holding the filing number, state and date. -/
  formationItem : Option String
  /-- The Proton Pass item holding the EIN. -/
  einItem : Option String
  registeredAgent : Option String
  documents : List Document
  deriving Repr

def Record.sharesSum (r : Record) : Nat := r.members.foldl (fun n m => n + m.percent) 0

/-- Owners whose shares sum to 100; managers exactly when manager-managed. -/
def Record.organized (r : Record) : Bool :=
  match r.management with
  | none => false
  | some .memberManaged => r.members ≠ [] && r.sharesSum = 100 && r.managers = []
  | some .managerManaged => r.members ≠ [] && r.sharesSum = 100 && r.managers ≠ []

def Record.holds (r : Record) (k : DocumentKind) : Bool := r.documents.any (·.kind == k)

/-- The state of formation is known: declared as the plan, or in the
formation item. -/
def Record.stateKnown (r : Record) : Bool := r.state.isSome || r.formationItem.isSome

/-- What a plan states. -/
def Record.plannedComplete (r : Record) : Bool :=
  r.purpose.isSome && r.organized && r.stateKnown

/-- What a formed company adds. -/
def Record.formedComplete (r : Record) : Bool :=
  r.formationItem.isSome && r.einItem.isSome && r.registeredAgent.isSome && r.holds .formation

def Record.activeComplete (r : Record) : Bool :=
  r.plannedComplete && r.formedComplete

/-- What a record must hold for a standing. -/
def completeFor : Status → Record → Bool
  | .natural, _ => true
  | .planned, r => r.plannedComplete
  | .forming, r => r.plannedComplete
  | .active, r => r.activeComplete
  | .dissolved, r => r.activeComplete

def Record.complete (r : Record) : Bool := completeFor r.status r

/-- A record complete for `active` is complete for `planned`. -/
theorem active_complete_planned (r : Record) (h : completeFor .active r = true) :
    completeFor .planned r = true := by
  simp only [completeFor, Record.activeComplete, Bool.and_eq_true] at h
  simpa [completeFor] using h.1

/-- An organized record's shares sum to exactly 100. -/
theorem organized_sum (r : Record) (h : r.organized = true) : r.sharesSum = 100 := by
  unfold Record.organized at h
  split at h <;> simp_all

/-- A complete plan knows its state, one way or the other. -/
theorem planned_state_known (r : Record) (h : completeFor .planned r = true) :
    r.state.isSome = true ∨ r.formationItem.isSome = true := by
  simp only [completeFor, Record.plannedComplete, Record.stateKnown, Bool.and_eq_true,
    Bool.or_eq_true] at h
  exact h.2

/-- An active record holds its formation document. -/
theorem active_holds_formation (r : Record) (h : completeFor .active r = true) :
    r.holds .formation = true := by
  simp only [completeFor, Record.activeComplete, Record.formedComplete, Bool.and_eq_true] at h
  exact h.2.2

end Kagamizo.Legal
