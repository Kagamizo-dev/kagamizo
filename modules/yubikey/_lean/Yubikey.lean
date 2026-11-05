/-
The hardware key as primary 2FA, SMS retired on purpose. Each account's
second factor (../default.nix renders them) is one method on a declared
key, or legacy SMS — and legacy SMS is admitted only with a stated reason,
so it is never kept silently. Lean decides, over every factor, that a
key-based method names a declared key and that every SMS factor has a
reason; the report then shows what is still on SMS to be moved.
-/
namespace Kagamizo.Yubikey

inductive Method where
  | fido2 | totp | piv | sms
  deriving DecidableEq, Repr

structure Factor where
  account : String
  method : Method
  /-- The key it is on; empty for SMS. -/
  key : String
  /-- Required for SMS (why it is still legacy). -/
  reason : String

def keyBased (m : Method) : Bool := m != .sms

/-- A factor is sound: a key method names a declared key; SMS has a reason. -/
def soundFactor (keys : List String) (f : Factor) : Bool :=
  if keyBased f.method then keys.contains f.key
  else f.reason != ""

def sound (keys : List String) (fs : List Factor) : Bool :=
  fs.all (soundFactor keys)

/-- In a sound set, every account still on SMS carries a reason — none is
kept silently. -/
theorem sms_is_reasoned (keys : List String) (fs : List Factor)
    (h : sound keys fs = true) (f : Factor) (hf : f ∈ fs) (hs : f.method = .sms) :
    f.reason ≠ "" := by
  have := List.all_eq_true.mp h f hf
  simp only [soundFactor, keyBased, hs] at this
  simpa using this

-- What the rule refuses, on stand-ins.
example : sound ["k1"] [{ account := "a", method := .fido2, key := "k2", reason := "" }] = false := by decide
example : sound ["k1"] [{ account := "a", method := .sms, key := "", reason := "" }] = false := by decide
example : sound ["k1"] [{ account := "a", method := .fido2, key := "k1", reason := "" }] = true := by decide
example : sound ["k1"] [{ account := "a", method := .sms, key := "", reason := "no security-key support" }] = true := by decide

end Kagamizo.Yubikey
