/-
The share-from-phone relay (modules/discord): what may cross from Discord
into the agents' Matrix room. A message is relayed only when its author is
the declared owner, its channel the declared one, and its author no bot.
`relayed` is the rule the Rust crate (../_src/src/relay.rs) implements; the
theorems are what it guarantees for any message, and ../default.nix renders
the declared ids after this file and has Lean decide them.
-/
namespace Kagamizo.Relay

/-- A Discord snowflake, as the digits Discord prints it with (the Nix
option type admits digits only). -/
structure Id where
  digits : String
  deriving DecidableEq, Repr

/-- What the relay reads of a Discord message. -/
structure Message where
  author : Id
  channel : Id
  bot : Bool
  deriving DecidableEq, Repr

/-- What the repository declares: the owner's user and the one channel. -/
structure Declared where
  owner : Id
  channel : Id
  deriving DecidableEq, Repr

/-- The rule. -/
def relayed (d : Declared) (m : Message) : Bool :=
  m.author == d.owner && m.channel == d.channel && !m.bot

/-- What reaches Matrix out of anything the gateway delivers. -/
def reaches (d : Declared) (ms : List Message) : List Message :=
  ms.filter (relayed d)

/-- A relayed message's author is the owner. -/
theorem relayed_author_is_owner (d : Declared) (m : Message) (h : relayed d m = true) :
    m.author = d.owner := by
  simp only [relayed, Bool.and_eq_true, beq_iff_eq] at h
  exact h.1.1

/-- A relayed message was posted in the declared channel. -/
theorem relayed_in_channel (d : Declared) (m : Message) (h : relayed d m = true) :
    m.channel = d.channel := by
  simp only [relayed, Bool.and_eq_true, beq_iff_eq] at h
  exact h.1.2

/-- A relayed message is never a bot's: the relay cannot feed itself. -/
theorem relayed_not_bot (d : Declared) (m : Message) (h : relayed d m = true) :
    m.bot = false := by
  simp only [relayed, Bool.and_eq_true, Bool.not_eq_eq_eq_not, Bool.not_true] at h
  exact h.2

/-- Only the owner's messages ever reach Matrix, whatever the gateway sends. -/
theorem reaches_only_owner (d : Declared) (ms : List Message) :
    ∀ m ∈ reaches d ms, m.author = d.owner := by
  intro m hm
  exact relayed_author_is_owner d m (List.mem_filter.mp hm).2

/-- Anyone else's message never reaches Matrix. -/
theorem other_never_reaches (d : Declared) (ms : List Message) (m : Message)
    (h : m.author ≠ d.owner) : m ∉ reaches d ms := by
  intro hm
  exact h (reaches_only_owner d ms m hm)

/-- Nothing from another channel reaches Matrix, the owner's included. -/
theorem elsewhere_never_reaches (d : Declared) (ms : List Message) (m : Message)
    (h : m.channel ≠ d.channel) : m ∉ reaches d ms := by
  intro hm
  exact h (relayed_in_channel d m (List.mem_filter.mp hm).2)

end Kagamizo.Relay
