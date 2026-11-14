/-
Mailbox cards (../cards.nix): a card hands one team the mail to one address,
from the senders it names, for what it says, until a day. The reader
(../_src/src/cards.rs) holds a message to its card; this file holds the
cards to the declarations.

  * a card's address is delivered: its domain is declared with a mailbox of
    that name or a catch-all, so mail to it lands somewhere we read;
  * no two cards share an address, so a message has one holder;
  * the holder serves the entity that owns the address's domain;
  * a card says what its holder may do, and none may send: mail leaves only
    as a batch the owner approved (../default.nix), until sending within a
    card's limits is built and proved.
-/
namespace Kagamizo.Mailbox

inductive May where
  | headers | bodies | draft | send
  deriving DecidableEq, Repr

structure Card where
  name : String
  address : String
  /-- The address's domain is declared, and mail to the address lands in a
  mailbox of it (its own, or the catch-all's). -/
  delivered : Bool
  /-- The entity that owns the address's domain. -/
  owner : String
  holder : String
  /-- The entity the holder serves. -/
  serves : String
  may : List May
  deriving Repr

def unique (cs : List Card) : Bool :=
  cs.all fun c => (cs.filter fun d => d.address == c.address).length == 1

def cardOk (c : Card) : Bool :=
  c.delivered && c.serves == c.owner && !c.may.isEmpty && !c.may.contains .send

def sound (cs : List Card) : Bool :=
  unique cs && cs.all cardOk

/-- No card of a sound set may send. -/
theorem no_card_sends (cs : List Card) (h : sound cs = true) (c : Card) (hc : c ∈ cs) :
    c.may.contains .send = false := by
  unfold sound at h
  simp only [Bool.and_eq_true] at h
  have hall := h.2
  rw [List.all_eq_true] at hall
  have hk := hall c hc
  unfold cardOk at hk
  simp only [Bool.and_eq_true, Bool.not_eq_true'] at hk
  exact hk.2

/-- A card's holder serves the entity whose address it is. -/
theorem holder_serves_the_owner (cs : List Card) (h : sound cs = true) (c : Card) (hc : c ∈ cs) :
    c.serves = c.owner := by
  unfold sound at h
  simp only [Bool.and_eq_true] at h
  have hall := h.2
  rw [List.all_eq_true] at hall
  have hk := hall c hc
  unfold cardOk at hk
  simp only [Bool.and_eq_true, Bool.not_eq_true'] at hk
  simpa using hk.1.1.2

/-- Mail to a card's address is delivered to a mailbox we read. -/
theorem card_is_delivered (cs : List Card) (h : sound cs = true) (c : Card) (hc : c ∈ cs) :
    c.delivered = true := by
  unfold sound at h
  simp only [Bool.and_eq_true] at h
  have hall := h.2
  rw [List.all_eq_true] at hall
  have hk := hall c hc
  unfold cardOk at hk
  simp only [Bool.and_eq_true, Bool.not_eq_true'] at hk
  exact hk.1.1.1

end Kagamizo.Mailbox
