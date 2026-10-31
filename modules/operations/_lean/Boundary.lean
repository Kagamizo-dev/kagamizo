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

/-- A typed field of a Proton Pass custom item (catalog/_json/pass-items.json). -/
inductive FieldKind where
  | text
  | hidden
  | totp
  | timestamp
  deriving DecidableEq, Repr

/-- Where a secret is kept in Proton Pass: a note's body, which automation
writes, or one typed field of an item made from an app template, which the
owner fills. -/
inductive Store where
  | note
  | field (template : String) (name : String) (kind : FieldKind)
  deriving DecidableEq, Repr

def Store.isField : Store → Bool
  | .field _ _ _ => true
  | .note => false

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
  store : Store
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

/-- Automation writes notes only; a field is filled by the owner, and a
token kept in a field is kept hidden. -/
def storedRightly (s : Secret) : Bool :=
  match s.store with
  | .note => true
  | .field _ _ k =>
    s.issuer.isHuman && (if s.kind = .apiToken then k = .hidden else true)

def wellFormed (s : Secret) : Bool := issuable s && waitsRightly s && storedRightly s

/-- No well-formed secret kept in a field was written by automation. -/
theorem field_by_hand (s : Secret) (hf : s.store.isField = true)
    (h : wellFormed s = true) : s.issuer.isHuman = true := by
  cases s with
  | mk n k i ns st =>
    cases st <;> simp_all [wellFormed, storedRightly, Store.isField]

/-- A well-formed token kept in a field is in a hidden one. -/
theorem token_field_hidden (s : Secret) (t n : String) (fk : FieldKind)
    (hk : s.kind = .apiToken) (hs : s.store = .field t n fk)
    (h : wellFormed s = true) : fk = .hidden := by
  cases s with
  | mk nm k i ns st =>
    subst hs; subst hk
    simp_all [wellFormed, storedRightly]

/-- No well-formed session is ever made by hand. -/
theorem session_by_automation (s : Secret) (hk : s.kind = .oauthSession)
    (h : wellFormed s = true) : s.issuer.isHuman = false := by
  cases s with
  | mk n k i ns st =>
    cases i <;> simp_all [wellFormed, issuable, Issuer.isHuman]

/-- No well-formed state or key is ever made by hand. -/
theorem state_and_keys_by_automation (s : Secret)
    (hk : s.kind = .state ∨ s.kind = .encryptionKey)
    (h : wellFormed s = true) : s.issuer.isHuman = false := by
  cases s with
  | mk n k i ns st =>
    rcases hk with hk | hk <;> cases i <;> simp_all [wellFormed, issuable, Issuer.isHuman]

/-- The only human step that ever issues a secret is placing a credential
a provider gives out in its console alone. -/
theorem human_issues_only_console_credentials (s : Secret) (step : HumanStep)
    (hi : s.issuer = .human step) (h : wellFormed s = true) :
    step = .consoleCredential := by
  cases s with
  | mk n k i ns st =>
    subst hi
    cases k <;> cases step <;> simp_all [wellFormed, issuable]

end Kagamizo
