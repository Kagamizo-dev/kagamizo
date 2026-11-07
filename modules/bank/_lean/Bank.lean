/-
The bank (../bank.nix): the owner's own bank, one app over the treasury,
the brokerages, trading, the books, tax, the legal record, the registered
agent and the rules. Lean decides it holds together: every account that
holds or moves money is held by one of the bank's services, so no money
sits outside it; every source of revenue lands in an account of its own
entity, an entity that is taxed and whose obligations are declared, so no
income is earned by an entity the bank cannot file for; and every service
is run by teams that exist.
-/
namespace Kagamizo.Bank

structure Service where
  name : String
  accounts : List String
  teams : List String
  deriving DecidableEq, Repr

structure Source where
  name : String
  entity : String
  account : String
  deriving DecidableEq, Repr

def ownerOf (owners : List (String × String)) (a : String) : String :=
  match owners.find? (·.1 == a) with
  | some (_, o) => o
  | none => ""

/-- A source is sound: it lands in its own entity's account, and the entity
is taxed and owes its declared obligations. -/
def sourceOk (owners : List (String × String)) (taxed owing : List String) (r : Source) : Bool :=
  ownerOf owners r.account == r.entity && taxed.contains r.entity && owing.contains r.entity

def unique : List String → Bool
  | [] => true
  | x :: xs => !xs.contains x && unique xs

def sound (moneyAccounts : List String) (owners : List (String × String)) (services : List Service)
    (revenue : List Source) (taxed owing teams : List String) : Bool :=
  unique (services.map (·.name)) && unique (revenue.map (·.name)) &&
  moneyAccounts.all (fun a => services.any (·.accounts.contains a)) &&
  revenue.all (sourceOk owners taxed owing) &&
  services.all (fun s => s.teams.all teams.contains)

/-- A sound source's entity is taxed: no revenue is earned by an entity the
bank does not file for. -/
theorem source_taxed (owners : List (String × String)) (taxed owing : List String) (r : Source)
    (h : sourceOk owners taxed owing r = true) : taxed.contains r.entity = true := by
  unfold sourceOk at h
  simp only [Bool.and_eq_true] at h
  exact h.1.2

end Kagamizo.Bank
