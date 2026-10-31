/-
The boundary between the owner and automation, as a specification.

The owner does only the steps in `HumanStep` (CLAUDE.md, "The one rule",
and the owner's decision of 2026-10-24); everything else is automation.
Every secret the repository declares has a `Kind`, an `Issuer` (a tool, or
one of those human steps) and the human steps an automated issuer waits on.
`wellFormed` is the rule; the theorems below are what it guarantees for any
secret, and ../default.nix checks every declared secret against it.
-/
namespace Kagamizo

/-- The only things the owner does by hand. -/
inductive HumanStep where
  /-- A 2FA link, push or code, or a captcha. -/
  | approveSignIn
  /-- Signing up for an account, identity checks included. -/
  | signUp
  | mintCard
  | cancelCard
  /-- A credential a provider issues only in its own console (a Gap). -/
  | consoleCredential
  /-- The bank's own approval to move money. -/
  | approvePayment
  /-- A signature, or an SSN, in a provider's portal. -/
  | signLegal
  deriving DecidableEq, Repr

/-- What a secret is. -/
inductive Kind where
  | apiToken
  | oauthSession
  | encryptionKey
  | state
  | passkey
  | identifier
  deriving DecidableEq, Repr

/-- Who produces a secret. -/
inductive Issuer where
  | automation (tool : String)
  | human (step : HumanStep)
  deriving DecidableEq, Repr

structure Secret where
  name : String
  kind : Kind
  issuer : Issuer
  /-- Human steps an automated issuer waits on. -/
  needs : List HumanStep
  deriving Repr

def Issuer.isHuman : Issuer → Bool
  | .human _ => true
  | .automation _ => false

/-- Who may issue which kind. A session, a passkey, a state or a key is
always made by automation (a session and a passkey after the owner approves
the sign-in); a token or an identifier the owner places only when a
provider issues it in its console alone. -/
def issuable (s : Secret) : Bool :=
  match s.kind, s.issuer with
  | .oauthSession, .automation _ => s.needs.contains .approveSignIn
  | .passkey, .automation _ => s.needs.contains .approveSignIn
  | .state, .automation _ => true
  | .encryptionKey, .automation _ => true
  | .apiToken, .automation _ => true
  | .identifier, .automation _ => true
  | .apiToken, .human .consoleCredential => true
  | .identifier, .human .consoleCredential => true
  | _, _ => false

/-- An automated issuer waits on sign-in approvals only; a human issuer
waits on nothing further. -/
def waitsRightly (s : Secret) : Bool :=
  if s.issuer.isHuman then s.needs.isEmpty else s.needs.all (· == .approveSignIn)

def wellFormed (s : Secret) : Bool := issuable s && waitsRightly s

/-- No well-formed session is ever made by hand. -/
theorem session_by_automation (s : Secret) (hk : s.kind = .oauthSession)
    (h : wellFormed s = true) : s.issuer.isHuman = false := by
  cases s with
  | mk n k i ns =>
    cases i <;> simp_all [wellFormed, issuable, Issuer.isHuman]

/-- No well-formed state or key is ever made by hand. -/
theorem state_and_keys_by_automation (s : Secret)
    (hk : s.kind = .state ∨ s.kind = .encryptionKey)
    (h : wellFormed s = true) : s.issuer.isHuman = false := by
  cases s with
  | mk n k i ns =>
    rcases hk with hk | hk <;> cases i <;> simp_all [wellFormed, issuable, Issuer.isHuman]

/-- The only human step that ever issues a secret is placing a credential
a provider gives out in its console alone. -/
theorem human_issues_only_console_credentials (s : Secret) (step : HumanStep)
    (hi : s.issuer = .human step) (h : wellFormed s = true) :
    step = .consoleCredential := by
  cases s with
  | mk n k i ns =>
    subst hi
    cases k <;> cases step <;> simp_all [wellFormed, issuable]

end Kagamizo
