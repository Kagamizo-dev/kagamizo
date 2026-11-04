/-
Proton Pass as an OpenTofu state backend: the write protocol, proven safe.

The backend (../_src, Rust) keeps one state as generations. A generation `g`
is `count` chunk items (`<name>@<g>#<i>`, each a note under the size limit)
and one manifest item (`<name>@<g>`) naming the count and the SHA-256 of the
joined chunks. A reader takes the newest *complete* generation: manifest
present and every chunk present (the hash is then checked by the reader).

Proton Pass offers only create, view and delete on an item; nothing is
updated in place. A write of a new state runs, in order:

  1. create every chunk of the new generation `n`,
  2. create its manifest,
  3. delete the old generation `o`'s manifest,
  4. delete `o`'s chunks.

Proven here, for any chunk counts: at every step of that sequence (so after
any failure part way through) some complete generation exists; when it
finishes, `n` is complete and `o` is gone. A write can therefore never lose
the state, which is how the first Cloudflare state was lost on 2026-11-01
(delete first, then a refused create). And chunking is lossless: joining
the chunks gives back the value, each chunk within the limit.

Locking is a lock item created only when absent: a second acquire fails.
-/
namespace Kagamizo.Store

/-- What the store holds of one generation. -/
structure Gen where
  manifest : Bool
  chunks : Nat
  count : Nat
  deriving DecidableEq, Repr

def Gen.complete (g : Gen) : Bool := g.manifest && g.chunks == g.count

/-- The store: every generation number to what is present of it. -/
abbrev Store := Nat → Gen

/-- The only operations Proton Pass offers on items. -/
inductive Op where
  | createChunk (g : Nat)
  | createManifest (g : Nat)
  | deleteManifest (g : Nat)
  | deleteChunk (g : Nat)
  deriving DecidableEq, Repr

def Op.gen : Op → Nat
  | .createChunk g | .createManifest g | .deleteManifest g | .deleteChunk g => g

def Op.onGen : Op → Gen → Gen
  | .createChunk _, x => { x with chunks := x.chunks + 1 }
  | .createManifest _, x => { x with manifest := true }
  | .deleteManifest _, x => { x with manifest := false }
  | .deleteChunk _, x => { x with chunks := x.chunks - 1 }

def apply (s : Store) (op : Op) : Store :=
  fun g => if g = op.gen then op.onGen (s g) else s g

def run (s : Store) (ops : List Op) : Store := ops.foldl apply s

/-- The write of generation `n` (with `count` chunks) over generation `o`
(with `old` chunks). -/
def write (o old n count : Nat) : List Op :=
  List.replicate count (.createChunk n) ++ [.createManifest n, .deleteManifest o]
    ++ List.replicate old (.deleteChunk o)

theorem run_append (s : Store) (a b : List Op) : run s (a ++ b) = run (run s a) b := by
  simp [run, List.foldl_append]

/-- Operations on other generations leave a generation as it was. -/
theorem run_other (s : Store) (ops : List Op) (g : Nat) (h : ∀ op ∈ ops, op.gen ≠ g) :
    run s ops g = s g := by
  induction ops generalizing s with
  | nil => rfl
  | cons op rest ih =>
    simp only [run, List.foldl_cons] at *
    rw [ih (apply s op) (fun o ho => h o (List.mem_cons_of_mem _ ho))]
    simp [apply, Ne.symm (h op List.mem_cons_self)]

theorem run_chunks (s : Store) (n k : Nat) :
    run s (List.replicate k (.createChunk n)) n = { s n with chunks := (s n).chunks + k } := by
  induction k generalizing s with
  | zero => simp [run]
  | succ k ih =>
    rw [List.replicate_succ]
    simp only [run, List.foldl_cons] at *
    rw [ih (apply s (.createChunk n))]
    simp [apply, Op.gen, Op.onGen, Nat.add_assoc, Nat.add_comm 1 k]

theorem take_replicate_gen (op : Op) (k m : Nat) :
    ∀ x ∈ (List.replicate m op).take k, x = op := by
  intro x hx
  exact List.eq_of_mem_replicate (List.mem_of_mem_take hx)

/-- The new generation starts empty. -/
def fresh (s : Store) (n count : Nat) : Prop :=
  s n = { manifest := false, chunks := 0, count := count }

/-- Safety: after any prefix of the write, some generation is complete. -/
theorem write_never_loses (s : Store) (o old n count k : Nat)
    (hne : o ≠ n) (hold : (s o).complete = true) (hfresh : fresh s n count) :
    (run s ((write o old n count).take k) o).complete = true ∨
    (run s ((write o old n count).take k) n).complete = true := by
  unfold write
  by_cases hk : k ≤ count
  · -- Still creating chunks: o is untouched.
    left
    rw [List.append_assoc, List.take_append_of_le_length (by simp; omega)]
    rw [run_other]
    · exact hold
    · intro op hop
      rw [take_replicate_gen _ _ _ op hop]
      simp [Op.gen]; omega
  · -- The new manifest is in: n is complete and nothing after touches it.
    right
    have hsplit : List.take k (List.replicate count (Op.createChunk n) ++
        [Op.createManifest n, Op.deleteManifest o] ++ List.replicate old (Op.deleteChunk o)) =
        List.replicate count (Op.createChunk n) ++
        List.take (k - count) ([Op.createManifest n, Op.deleteManifest o] ++
          List.replicate old (Op.deleteChunk o)) := by
      rw [List.append_assoc, List.take_append, List.take_of_length_le (by simp; omega)]
      simp
    rw [hsplit, run_append]
    obtain ⟨j, hj⟩ : ∃ j, k - count = j + 1 := ⟨k - count - 1, by omega⟩
    rw [hj]
    simp only [List.cons_append, List.nil_append, List.take_succ_cons]
    rw [show ∀ (t : Store) (a : Op) (l : List Op), run t (a :: l) = run (apply t a) l from
      fun _ _ _ => rfl]
    rw [run_other _ _ n (by
      intro op hop
      have hm := List.mem_of_mem_take hop
      simp only [List.mem_cons] at hm
      rcases hm with h | h
      · subst h; simp [Op.gen]; exact hne
      · rw [List.eq_of_mem_replicate h]; simp [Op.gen]; exact hne)]
    have hc := run_chunks s n count
    simp only [fresh] at hfresh
    simp [apply, Op.gen, Op.onGen, hc, Gen.complete, hfresh]

/-- Liveness: once the write finishes, the new generation is complete and the
old one has neither manifest nor chunks. -/
theorem write_completes (s : Store) (o old n count : Nat)
    (hne : o ≠ n) (hold : (s o).chunks = old) (hfresh : fresh s n count) :
    (run s (write o old n count) n).complete = true ∧
    (run s (write o old n count) o).manifest = false ∧
    (run s (write o old n count) o).chunks = 0 := by
  simp only [fresh] at hfresh
  refine ⟨?_, ?_, ?_⟩ <;> unfold write <;> rw [run_append, run_append]
  · rw [run_other _ _ n (by intro op hop; rw [List.eq_of_mem_replicate hop]; simp [Op.gen]; exact hne)]
    simp [run, apply, Op.gen, Op.onGen]
    have hc := run_chunks s n count
    simp only [run] at hc
    simp [hc, Gen.complete, hfresh, Ne.symm hne]
  · -- the manifest of o is deleted, and chunk deletions keep it deleted
    have key : ∀ (t : Store) (m : Nat), (t o).manifest = false →
        (run t (List.replicate m (Op.deleteChunk o)) o).manifest = false := by
      intro t m ht
      induction m generalizing t with
      | zero => simpa [run] using ht
      | succ m ih =>
        rw [List.replicate_succ]
        simp only [run, List.foldl_cons] at *
        apply ih
        simp [apply, Op.gen, Op.onGen, ht]
    apply key
    simp [run, apply, Op.gen, Op.onGen]
  · have key : ∀ (t : Store) (m : Nat),
        (run t (List.replicate m (Op.deleteChunk o)) o).chunks = (t o).chunks - m := by
      intro t m
      induction m generalizing t with
      | zero => simp [run]
      | succ m ih =>
        rw [List.replicate_succ]
        simp only [run, List.foldl_cons] at *
        rw [ih]
        simp [apply, Op.gen, Op.onGen]; omega
    rw [key]
    have ho : run s (List.replicate count (Op.createChunk n)) o = s o :=
      run_other _ _ _ (by intro op hop; rw [List.eq_of_mem_replicate hop]; simp [Op.gen]; omega)
    simp [run] at ho
    simp [run, apply, Op.gen, Op.onGen, hne, ho, hold]

/-! Chunking. -/

/-- Split into pieces of at most `size` (size > 0). -/
def chunk {α : Type} (size : Nat) : List α → List (List α)
  | [] => []
  | x :: xs =>
    if _h : size = 0 then [x :: xs]
    else (x :: xs).take size :: chunk size ((x :: xs).drop size)
termination_by l => l.length
decreasing_by simp; omega

theorem chunk_join {α : Type} (size : Nat) (l : List α) : (chunk size l).flatten = l := by
  induction l using (measure List.length).wf.induction with
  | h l ih =>
    match l with
    | [] => simp [chunk]
    | x :: xs =>
      unfold chunk
      by_cases h : size = 0
      · simp [h]
      · simp only [h, dite_false, List.flatten_cons]
        rw [ih _ (by show (List.drop size (x :: xs)).length < (x :: xs).length; simp; omega)]
        exact List.take_append_drop size (x :: xs)

theorem chunk_small {α : Type} (size : Nat) (hs : 0 < size) (l : List α) :
    ∀ c ∈ chunk size l, c.length ≤ size := by
  induction l using (measure List.length).wf.induction with
  | h l ih =>
    match l with
    | [] => simp [chunk]
    | x :: xs =>
      intro c hc
      unfold chunk at hc
      have hz : size ≠ 0 := by omega
      simp only [hz, dite_false, List.mem_cons] at hc
      rcases hc with rfl | hc
      · exact List.length_take_le _ _
      · exact ih _ (by show (List.drop size (x :: xs)).length < (x :: xs).length; simp; omega) c hc

/-! Locking. -/

/-- A lock is an item; acquiring creates it only when it is absent. -/
def acquire (locked : Bool) : Option Bool := if locked then none else some true

theorem acquire_exclusive : acquire true = none := rfl
theorem acquire_free : acquire false = some true := rfl

end Kagamizo.Store
