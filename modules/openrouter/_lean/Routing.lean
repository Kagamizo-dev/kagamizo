/-
OpenRouter routing by typed expectations (../routing.nix). A class bounds
the price of each kind of token, the precisions accepted, and the uptime,
time to first token and throughput it needs; ../routing.nix derives the
endpoints that meet the bounds from the dated price and performance
measurements and renders each class with them after this file. Lean
decides that each class keeps at least one endpoint and that every one it
allows meets every bound. Numbers are integers: micro-dollars per million
tokens, hundredths of a percent, milliseconds, tenths of a token a second.
-/
namespace Kagamizo.Routing

structure Class where
  name : String
  quants : List String
  maxInput : Nat
  maxCacheRead : Nat
  maxOutput : Nat
  minUptime : Nat
  maxTtftMs : Nat
  minTps : Nat
  deriving Repr

structure Endpoint where
  tag : String
  quant : String
  input : Nat
  cacheRead : Nat
  output : Nat
  uptime : Nat
  ttftMs : Nat
  tps : Nat
  deriving Repr

/-- One endpoint meets every bound of its class. -/
def meets (c : Class) (e : Endpoint) : Bool :=
  decide (e.input ≤ c.maxInput) && decide (e.cacheRead ≤ c.maxCacheRead) &&
  decide (e.output ≤ c.maxOutput) && c.quants.contains e.quant &&
  decide (c.minUptime ≤ e.uptime) && decide (e.ttftMs ≤ c.maxTtftMs) &&
  decide (c.minTps ≤ e.tps)

/-- A class is sound when it can be routed somewhere, and everywhere it
can be routed meets its bounds. -/
def sound (c : Class) (es : List Endpoint) : Bool :=
  !es.isEmpty && es.all (meets c)

/-- A sound class's endpoints are all within its cache-read price: the
bound agent loops' bills depend on. -/
theorem sound_within_cache_price (c : Class) (es : List Endpoint) (h : sound c es = true)
    (e : Endpoint) (he : e ∈ es) : e.cacheRead ≤ c.maxCacheRead := by
  unfold sound at h
  simp only [Bool.and_eq_true, List.all_eq_true] at h
  have := h.2 e he
  unfold meets at this
  simp only [Bool.and_eq_true, decide_eq_true_eq] at this
  exact this.1.1.1.1.1.2

end Kagamizo.Routing
