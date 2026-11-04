/-
The media pipeline's cut-list rule (modules/media): what a cut list must
satisfy before the renderer (../_src, Rust) touches a clip. Every time is
a whole number of milliseconds, in the catalog, in the cut list and here,
so the Rust validator and this file decide the same numbers.

A catalogued clip (`Clip`, the schema `media.clips` states in Nix) has a
duration. A cut list names one clip, lists segments of it and the length
asked for. It is valid when

  1. every segment is non-empty and ends within the clip,
  2. each segment ends no later than the next starts (ordered, so never
     overlapping),
  3. the segments add up to the target within the declared tolerance,
  4. the target and the total are at most the longest clip allowed.

Proven: a valid cut list never reads past the end of its clip, and what it
renders is bounded by `maxClipSeconds`. ../default.nix renders the
declared limits after this file and Lean decides them too.
-/
namespace Kagamizo.Clips

/-- One line of a transcript. -/
structure Line where
  startMs : Nat
  endMs : Nat
  text : String
  deriving DecidableEq, Repr

/-- A catalogued clip, as `media.clips` types it (fps and the scene
threshold are decimals in the JSON; here they are the strings the renderer
never computes with). -/
structure Clip where
  id : String
  source : String
  date : String
  durationMs : Nat
  width : Nat
  height : Nat
  codec : String
  fps : String
  hasAudio : Bool
  sceneThreshold : String
  scenes : List Nat
  whisperModel : Option String
  transcript : List Line
  deriving Repr

/-- A segment of the source, `[startMs, endMs)`. -/
structure Segment where
  startMs : Nat
  endMs : Nat
  deriving DecidableEq, Repr

def Segment.len (s : Segment) : Nat := s.endMs - s.startMs

/-- Non-empty, and ending within a clip of the given duration. -/
def Segment.within (d : Nat) (s : Segment) : Bool :=
  s.startMs < s.endMs && s.endMs ≤ d

structure CutList where
  source : String
  segments : List Segment
  targetMs : Nat
  deriving DecidableEq, Repr

/-- Each segment ends no later than the next starts. -/
def ordered : List Segment → Bool
  | a :: b :: rest => a.endMs ≤ b.startMs && ordered (b :: rest)
  | _ => true

def CutList.total (c : CutList) : Nat := (c.segments.map Segment.len).sum

/-- Within `tol` of the target, either way. -/
def CutList.onTarget (tol : Nat) (c : CutList) : Bool :=
  c.targetMs ≤ c.total + tol && c.total ≤ c.targetMs + tol

/-- The rule, for a clip of duration `d`, a tolerance `tol` and the longest
clip allowed `maxMs`. -/
def valid (d tol maxMs : Nat) (c : CutList) : Bool :=
  !c.segments.isEmpty
    && c.segments.all (Segment.within d)
    && ordered c.segments
    && c.onTarget tol
    && c.targetMs ≤ maxMs
    && c.total ≤ maxMs

/-- A valid cut list never reads past the end of its clip. -/
theorem never_past_end {d tol maxMs : Nat} {c : CutList} (h : valid d tol maxMs c = true) :
    ∀ s ∈ c.segments, s.endMs ≤ d := by
  intro s hs
  simp only [valid, Bool.and_eq_true, List.all_eq_true] at h
  have hw := h.1.1.1.1.2 s hs
  simp only [Segment.within, Bool.and_eq_true, decide_eq_true_eq] at hw
  exact hw.2

/-- Nor before its start: every segment is non-empty. -/
theorem never_empty {d tol maxMs : Nat} {c : CutList} (h : valid d tol maxMs c = true) :
    ∀ s ∈ c.segments, s.startMs < s.endMs := by
  intro s hs
  simp only [valid, Bool.and_eq_true, List.all_eq_true] at h
  have hw := h.1.1.1.1.2 s hs
  simp only [Segment.within, Bool.and_eq_true, decide_eq_true_eq] at hw
  exact hw.1

/-- What a valid cut list renders is no longer than the longest clip
allowed: the renderer's output is the segments' total. -/
theorem length_bounded {d tol maxMs : Nat} {c : CutList} (h : valid d tol maxMs c = true) :
    c.total ≤ maxMs := by
  simp only [valid, Bool.and_eq_true, decide_eq_true_eq] at h
  exact h.2

/-- And it is what was asked for, within the tolerance. -/
theorem on_target {d tol maxMs : Nat} {c : CutList} (h : valid d tol maxMs c = true) :
    c.targetMs ≤ c.total + tol ∧ c.total ≤ c.targetMs + tol := by
  simp only [valid, CutList.onTarget, Bool.and_eq_true, decide_eq_true_eq] at h
  exact h.1.1.2

/-- Ordered segments never overlap: each ends before the next starts. -/
theorem ordered_adjacent : ∀ (l : List Segment), ordered l = true →
    ∀ i (hi : i + 1 < l.length), (l[i]).endMs ≤ (l[i + 1]).startMs
  | [], _, i, hi => nomatch hi
  | [_], _, i, hi => by simp at hi
  | a :: b :: rest, h, i, hi => by
    simp only [ordered, Bool.and_eq_true, decide_eq_true_eq] at h
    cases i with
    | zero => exact h.1
    | succ j =>
      have := ordered_adjacent (b :: rest) h.2 j (by simpa using hi)
      simpa using this

/-- Rejected: the examples the Rust validator's test walks too. -/
example : valid 60000 500 120000 ⟨"c", [⟨1000, 3000⟩, ⟨5000, 6000⟩], 3000⟩ = true := by decide
example : valid 60000 500 120000 ⟨"c", [⟨59000, 60001⟩], 1000⟩ = false := by decide
example : valid 60000 500 120000 ⟨"c", [⟨5000, 5000⟩], 0⟩ = false := by decide
example : valid 60000 500 120000 ⟨"c", [⟨1000, 3000⟩, ⟨2500, 4000⟩], 3500⟩ = false := by decide
example : valid 60000 500 120000 ⟨"c", [⟨1000, 3000⟩, ⟨3000, 4000⟩], 3000⟩ = true := by decide
example : valid 60000 500 120000 ⟨"c", [⟨0, 2499⟩], 3000⟩ = false := by decide
example : valid 200000 500 120000 ⟨"c", [⟨0, 120400⟩], 120000⟩ = false := by decide
example : valid 60000 500 120000 ⟨"c", [], 0⟩ = false := by decide

end Kagamizo.Clips
