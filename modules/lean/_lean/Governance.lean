/-
Every operation a wrapper exposes, typed (modules/governance): what it does
to an account, and what it runs. An action that runs a pinned tool's
command names that command in the tool's catalog (Api.lean), and Lean
checks it is there; one that runs a wrapper of ours names the program.

The base layer the Cedar policy holds is stated here too: an agent may only
be granted reading and writing, never spending, destroying or signing in.
../default.nix renders every declared action and grant, and Lean proves
each one keeps these rules.
-/
namespace Kagamizo.Governance
open Kagamizo.Api

inductive Effect where
  | read
  | write
  | spend
  | destroy
  | session
  | moveLogin
  deriving DecidableEq, Repr

/-- What an action runs. -/
inductive Runs where
  /-- A command of a pinned tool, by its catalog name and its words. -/
  | command (api : String) (op : String)
  /-- A wrapper of ours (`cards`, `browser`, `mailbox`, ...), or a tool of an
  MCP server ours wraps. -/
  | wrapper (program : String)
  deriving DecidableEq, Repr

structure Action where
  provider : String
  name : String
  effect : Effect
  runs : Runs
  deriving Repr

/-- The effects an agent may ever be granted. -/
def agentMay : Effect → Bool
  | .read | .write => true
  | _ => false

structure Grant where
  agent : String
  account : String
  effects : List Effect
  deriving Repr

def Grant.allowed (g : Grant) : Bool := g.effects.all agentMay

/-- An allowed grant never lets an agent spend, destroy or sign in. -/
theorem allowed_grant_never_spends (g : Grant) (h : g.allowed = true) :
    .spend ∉ g.effects ∧ .destroy ∉ g.effects ∧ .session ∉ g.effects := by
  have hall := List.all_eq_true.mp h
  refine ⟨fun hm => ?_, fun hm => ?_, fun hm => ?_⟩ <;>
    simpa [agentMay] using hall _ hm

/-- An action's command is one its API has. -/
def Action.typed (apis : List Api) (a : Action) : Bool :=
  match a.runs with
  | .command api op => apis.any fun x => x.name == api && (x.find op).isSome
  | .wrapper _ => true

end Kagamizo.Governance
