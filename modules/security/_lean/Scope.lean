/-
The security scope (../security.nix): what may be tested, and through what.
An online asset is tested through the account that hosts it, by a probe
grant Cedar authorizes (../../governance); this file decides the scope
itself: every online asset names an account we hold; every hostname lies
under a domain of the entity that owns it, so no one else's name is ever
in scope; every host or hostname is reachable by a probe grant on its
account; and every probe grant is for an account that hosts something in
scope, so no grant probes more than the scope.
-/
namespace Kagamizo.Security

inductive Kind where
  | host | hostname | repo | image | device
  deriving DecidableEq, Repr

structure Asset where
  name : String
  kind : Kind
  asset : String
  /-- The account that hosts it; "" for an offline asset. -/
  account : String
  entity : String
  deriving DecidableEq, Repr

def online (k : Kind) : Bool := k == .host || k == .hostname || k == .repo

/-- Probed live, through a probe grant (a repository is read, not probed). -/
def probed (k : Kind) : Bool := k == .host || k == .hostname

def underDomain (asset d : String) : Bool :=
  asset == d || asset.endsWith ("." ++ d)

/-- The asset is a name under one of its entity's own domains. -/
def ownDomain (domains : List (String × String)) (a : Asset) : Bool :=
  domains.any fun (d, e) => e == a.entity && underDomain a.asset d

def assetOk (domains owners probes : List (String × String)) (a : Asset) : Bool :=
  (!online a.kind || (!a.account.isEmpty && owners.any (·.1 == a.account))) &&
  (a.kind != .hostname || ownDomain domains a) &&
  (!probed a.kind || probes.any (·.2 == a.account))

def unique : List String → Bool
  | [] => true
  | x :: xs => !xs.contains x && unique xs

def sound (scope : List Asset) (domains owners probes : List (String × String)) : Bool :=
  unique (scope.map (·.name)) &&
  scope.all (assetOk domains owners probes) &&
  probes.all fun (_, acc) => scope.any fun a => a.account == acc && probed a.kind

/-- A hostname in a sound scope is a name under its owner's own domain. -/
theorem hostname_is_ours (domains owners probes : List (String × String)) (a : Asset)
    (h : assetOk domains owners probes a = true) (hk : a.kind = .hostname) :
    ownDomain domains a = true := by
  unfold assetOk at h
  simp [hk] at h
  exact h.1.2

end Kagamizo.Security
