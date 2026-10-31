/-
Every API the modules use, as one typed model: a command-line tool, an HTTP
API and an OpenTofu provider are each a set of operations taking typed
inputs, and a call is accepted when it names an operation, gives only that
operation's inputs, each a value of its type, and every required one.

The catalogs (../../catalog/_json, extracted from the pinned tools) are
rendered into this model by ../default.nix, one Lean file each; the
theorems below are what `accepts` guarantees for any of them.
-/
namespace Kagamizo.Api

/-- The type of one input, as the pinned tool states it. -/
inductive Ty where
  | string
  | bool
  /-- An option that takes no value: present or not. -/
  | flag
  | int
  | number
  | duration
  | ip
  | cidr
  /-- A JSON value, or a nested block (an object, an OpenTofu block). -/
  | json
  /-- key=value pairs. -/
  | pairs
  | list (of : Ty)
  | oneOf (values : List String)
  /-- A type the same catalog declares (`Api.types`, `Api.enums`). -/
  | named (name : String)
  deriving DecidableEq, Repr, Inhabited

structure Input where
  name : String
  ty : Ty
  required : Bool := false
  deriving DecidableEq, Repr, Inhabited

/-- A command (its words), an HTTP operation (its id) or a provider's
resource or data source (its type name). -/
structure Operation where
  name : String
  inputs : List Input
  deriving Repr, Inhabited

/-- A record type an HTTP API declares, by its fields. -/
structure TypeDecl where
  name : String
  fields : List Input
  deriving Repr

structure Api where
  name : String
  /-- The pinned version the catalog was extracted from. -/
  version : String
  ops : List Operation
  types : List TypeDecl := []
  enums : List (String × List String) := []
  deriving Repr

/-- A value given to an input. -/
inductive Value where
  | str (s : String)
  | bool (b : Bool)
  | int (i : Int)
  /-- Present, for a flag. -/
  | set
  | list (vs : List Value)
  /-- Known only when the script runs (a shell variable); the tool checks it then. -/
  | runtime
  deriving Repr, Inhabited

/-- Whether a value may be given to an input of a type. A string stands for
any scalar a tool reads from its command line; enums are checked by value. -/
def Value.fits : Value → Ty → Bool
  | .runtime, _ => true
  | .set, .flag => true
  | .bool _, .flag => true
  | .bool _, .bool => true
  | .int _, .int => true
  | .int _, .number => true
  | .str _, .string => true
  | .str _, .duration => true
  | .str _, .ip => true
  | .str _, .cidr => true
  | .str _, .json => true
  | .str _, .pairs => true
  | .str _, .named _ => true
  | .str s, .oneOf vs => vs.contains s
  | .list vs, .list t => vs.attach.all fun ⟨v, _⟩ => v.fits t
  | .list _, .json => true
  | .list _, .pairs => true
  | _, _ => false

structure Call where
  op : String
  given : List (String × Value)
  deriving Repr

def Api.find (api : Api) (op : String) : Option Operation :=
  api.ops.find? (·.name == op)

def Operation.input (o : Operation) (n : String) : Option Input :=
  o.inputs.find? (·.name == n)

/-- Every given input is the operation's, with a value of its type. -/
def Operation.known (o : Operation) (c : Call) : Bool :=
  c.given.all fun p => match o.input p.1 with
    | some i => p.2.fits i.ty
    | none => false

/-- Every required input is given. -/
def Operation.complete (o : Operation) (c : Call) : Bool :=
  o.inputs.all fun i => !i.required || c.given.any (·.1 == i.name)

def Api.accepts (api : Api) (c : Call) : Bool :=
  match api.find c.op with
  | some o => o.known c && o.complete c
  | none => false

/-- An accepted call names one of the API's operations. -/
theorem accepts_names_an_operation (api : Api) (c : Call) (h : api.accepts c = true) :
    ∃ o, api.find c.op = some o := by
  unfold Api.accepts at h
  split at h
  · exact ⟨_, ‹_›⟩
  · contradiction

/-- An accepted call gives only the operation's inputs, each a value of its type. -/
theorem accepts_only_typed_inputs (api : Api) (c : Call) (o : Operation)
    (ho : api.find c.op = some o) (h : api.accepts c = true) :
    ∀ p ∈ c.given, ∃ i, o.input p.1 = some i ∧ p.2.fits i.ty = true := by
  intro p hp
  simp only [Api.accepts, ho, Bool.and_eq_true] at h
  have hk := List.all_eq_true.mp h.1 p hp
  cases hi : o.input p.1 with
  | none => simp [hi] at hk
  | some i => simp only [hi] at hk; exact ⟨i, rfl, hk⟩

/-- An accepted call gives every input the operation requires. -/
theorem accepts_every_required (api : Api) (c : Call) (o : Operation)
    (ho : api.find c.op = some o) (h : api.accepts c = true) :
    ∀ i ∈ o.inputs, i.required = true → ∃ p ∈ c.given, p.1 = i.name := by
  intro i hi hr
  simp only [Api.accepts, ho, Bool.and_eq_true] at h
  have := List.all_eq_true.mp h.2 i hi
  simp only [hr, Bool.not_true, Bool.false_or, List.any_eq_true, beq_iff_eq] at this
  exact this

/-- A call naming no operation is never accepted, whatever it gives. -/
theorem unknown_operation_refused (api : Api) (c : Call) (h : api.find c.op = none) :
    api.accepts c = false := by
  simp [Api.accepts, h]

/-- Every type a catalog's declarations refer to by name is one it declares. -/
def Api.closed (api : Api) : Bool :=
  let declared := api.types.map (·.name) ++ api.enums.map (·.1)
  let rec refs : Ty → List String
    | .named n => [n]
    | .list t => refs t
    | _ => []
  let inputs := api.ops.flatMap (·.inputs) ++ api.types.flatMap (·.fields)
  inputs.all fun i => (refs i.ty).all declared.contains

end Kagamizo.Api
