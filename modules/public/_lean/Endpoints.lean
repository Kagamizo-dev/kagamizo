/-
Public's HTTP API as the Rust client is bound to it (../endpoints.nix).
The client's table, the declared endpoints with their evidence
(../authorization.nix), the typed governance actions and the client's
bounds are rendered after this file; Lean decides they agree: the table is
the declared endpoints, every endpoint is an action with the same effect
and a command that calls it, only orders spend, the reader neither writes
nor spends, and the placer adds exactly the single-leg order. The order
lifecycle is Public's own statuses.
-/
namespace Kagamizo.PublicApi

inductive Effect where
  | session | read | write | spend
  deriving DecidableEq, Repr

/-- An endpoint in the Rust client's table. -/
structure Endpoint where
  name : String
  method : String
  path : String
  command : String
  effect : Effect
  deriving DecidableEq, Repr

/-- An endpoint as ../authorization.nix declares it, with the state of the
evidence that it answers this account. -/
structure Declared where
  name : String
  method : String
  path : String
  state : String
  deriving DecidableEq, Repr

/-- The table and the declaration name the same endpoints, in the same
order, with the same method and path. -/
def sameAs (t : List Endpoint) (d : List Declared) : Bool :=
  t.map (fun e => (e.name, e.method, e.path)) == d.map (fun e => (e.name, e.method, e.path))

/-- Every endpoint is one its command's handler calls. -/
def called (calls : List (String × List String)) (t : List Endpoint) : Bool :=
  t.all fun e => calls.any fun (c, eps) => c == e.command && eps.contains e.name

/-- Every endpoint a bound names has evidence it answers this account. -/
def runnable (d : List Declared) (bound : List String) : Bool :=
  bound.all fun n => d.any fun e => e.name == n && (e.state == "observed" || e.state == "documented")

structure Action where
  command : String
  effect : Effect
  deriving DecidableEq, Repr

/-- Every endpoint is a declared governance action, with the same effect. -/
def typed (actions : List Action) (es : List Endpoint) : Bool :=
  es.all fun e => actions.any fun a => a.command == e.command && a.effect == e.effect

/-- The endpoints of one effect, by name. -/
def ofEffect (k : Effect) (es : List Endpoint) : List String :=
  (es.filter (·.effect == k)).map (·.name)

def effectOf (es : List Endpoint) (n : String) : Option Effect :=
  (es.find? (·.name == n)).map (·.effect)

/-- A client's bound neither writes nor spends. -/
def readOnly (es : List Endpoint) (bound : List String) : Bool :=
  bound.all fun n => match effectOf es n with
    | some .read | some .session => true
    | _ => false

/-- What one bound may call that another may not. -/
def beyond (wide narrow : List String) : List String :=
  wide.filter (!narrow.contains ·)

/-- Every name a bound lists is an endpoint. -/
def known (es : List Endpoint) (bound : List String) : Bool :=
  bound.all fun n => (effectOf es n).isSome

/-! The order lifecycle: Public's GatewayOrderStatus. -/

inductive OrderStatus where
  | new | partiallyFilled | pendingCancel | pendingReplace | queuedCancelled
  | filled | cancelled | expired | rejected | replaced
  deriving DecidableEq, Repr

def OrderStatus.all : List OrderStatus :=
  [.new, .partiallyFilled, .pendingCancel, .pendingReplace, .queuedCancelled,
   .filled, .cancelled, .expired, .rejected, .replaced]

/-- Ended: `trade place` reads an order back until it is. -/
def OrderStatus.terminal : OrderStatus → Bool
  | .filled | .cancelled | .expired | .rejected | .replaced => true
  | _ => false

/-- A partial fill is still working: reading back does not stop there. -/
theorem partial_fill_works : OrderStatus.partiallyFilled.terminal = false := rfl

/-- Five ways an order ends, and a fill is one. -/
theorem five_ends :
    (OrderStatus.all.filter OrderStatus.terminal).length = 5 ∧ OrderStatus.filled.terminal = true := by
  decide

/-- A bound that neither writes nor spends keeps that when narrowed. -/
theorem readOnly_narrows (es : List Endpoint) (n : String) (b : List String)
    (h : readOnly es (n :: b) = true) : readOnly es b = true := by
  unfold readOnly at *
  simp only [List.all_cons, Bool.and_eq_true] at h
  exact h.2

end Kagamizo.PublicApi
