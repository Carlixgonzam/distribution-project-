# Why the document converges

The document is Treedoc [T] written as a delta-state CRDT [A]. This file argues that it is one, and points to the tests that check each claim.

- [T] Preguiça, Marquès, Shapiro, Leția. A commutative replicated data type for cooperative editing. ICDCS 2009.
- [A] Almeida, Shoker, Baquero. Delta state replicated data types. JPDC 2018.
- [S] Shapiro, Preguiça, Baquero, Zawirski. Conflict-free Replicated Data Types. INRIA RR-7687, 2011.

## 1. The state is a join-semilattice

What travels is `%{atomos, borrados}` (`Treedoc.vacio/0`). `contador` and `ultimo` stay in the replica, they are never sent or merged, and the tests compare only `atomos` and `borrados`.

The state is a pair `S = A × T`:

- `T`, the tombstones: sets of posids, ordered by ⊆, join ∪. A grow-only set ([A] Fig. 5).
- `A`, the atoms: finite maps posid → char. `a ⊑ a'` when every key of `a` is in `a'` with `a(p) ≤ a'(p)` in Erlang term order. Chars are binaries, which term order sorts totally, so the join is the merge of both maps keeping `max` on shared keys.
- The pair is ordered and joined component by component ([A] §7.1.1, Fig. 3). The bottom is `(%{}, ∅)`, which is `vacio()`.

`Treedoc.merge/2` is that join: `Map.merge` with `max`, plus `MapSet.union`. Both are commutative, associative and idempotent, so `merge` is too. It is the two-phase set of [A] Fig. 6, with a map as the add part.

Test: "leyes del merge y convergencia en 200 ejecuciones aleatorias de 3 réplicas".

## 2. insertar and borrar are δ-mutators

A δ-mutator returns a state of `S` ([A] Def. 4.1), and the replica moves to `X ⊔ mδ(X)` ([A] Def. 4.3).

| operation | delta |
|---|---|
| `insertar(X, i, c)` | `({n ↦ c}, ∅)`, `n` a new posid between the neighbours of position `i` |
| `borrar(X, i)` | `(∅, {posid of the i-th visible char})` |

Both return `{merge(X, delta), delta}`, so every transition of a replica is a join, either with a local delta or with a received message. A received message is a delta or a full state, and a full state is just a large delta-group ([A] §4).

The deltas don't need to be inflations; joining them makes the new state one: `X ⊑ X ⊔ δ`. That is the monotonic semilattice of [S] Def. 2.4.

Test: "δ-mutadores: cada operación local es X ⊔ delta, infla el estado y no repite PosID" checks `X ⊔ δ == X'` and `X ⊑ X'` after every local operation in 200 random runs.

## 3. Convergence despite loss, duplication and reordering

`texto/1` only reads the state: visible atoms sorted with `menor?`. So equal states give the same text.

[A] Prop. 5.1: if every delta reaches every replica at least once, directly or inside a delta-group, all states become equal. `CpdDoc.Replica` is the basic anti-entropy of [A] Algorithm 1 in direct mode:

- After a local operation, it sends the delta to every node in `Node.list()`.
- On `:nodeup` and every 30 s, it sends the full state.

What happens with each failure:

| failure | why it's fine |
|---|---|
| a delta is lost | the next full state carries it |
| a delta arrives twice, e.g. queued messages after a reconnect | `X ⊔ δ ⊔ δ = X ⊔ δ` |
| deltas arrive out of order | ⊔ is commutative and associative |
| partition | both sides keep editing, and on `:nodeup` they exchange full states |
| two nodes never talk directly | a third node's full state contains what it merged |

This is [S] Theorem 2.1: with eventual delivery and a monotonic semilattice, the object is SEC ([S] Def. 2.3).

**Why every 30 s** (`@difundir_cada` in `CpdDoc.Replica`). [A] only says "periodically" and [S] "infinitely often". Deltas and `:nodeup` leave three gaps that only the periodic resend closes:

- Erlang takes 45 to 75 s (`net_ticktime`, 60 s by default) to notice a dead link. A delta sent in that window is lost, and if the link never goes down for Erlang there is no `:nodeup` either.
- If `CpdDoc.Replica` crashes and the supervisor restarts it, the nodes stay connected, so no `:nodeup` arrives. It loads what it saved (§8) and gets the last few seconds from the others' next resend.
- Two nodes that never talk directly only learn about each other through a third node's full state.

Shorter repairs sooner, but each resend is the whole document to every neighbour, over a phone hotspot shared by up to 13 devices: a few hundred KB for a demo-sized text, 2 to 4 MB for 2000 chars. 30 s is about how long Erlang takes to notice a failure anyway. PROTOCOL.md leaves the value open.

**`prevent_overlapping_partitions false`** (in `rel/vm.args.eex`). With the OTP default, when one link drops, `global` also cuts the node's other links, so it is left alone until the next subnet sweep (10 s on the Pi, never on a laptop). We saw it with 3 nodes: when `c` dropped, `a` lost `b` too. We use no global names, and the document converges again on reconnect anyway, so that isolation buys nothing.

## 4. No causal delivery needed

Op-based Treedoc replays operations "as long as happened-before order is satisfied", and "an insert must happen-before a delete with the same identifier" ([T] §2.2). Here nothing has to arrive first:

- `menor?` compares paths only. No tree is built, so an atom whose ancestors haven't arrived still sorts correctly against every other atom.
- A tombstone that arrives before its atom is kept, and it hides the atom when the atom arrives (vector V4 in [PROTOCOL.md](../PROTOCOL.md)).
- The join is defined for any two states, so no message ever waits in a buffer.

What we give up is causal consistency of the intermediate states: for a moment a replica can show a char without the one typed before it. Converging doesn't need it. If we want it, [A] §6 gets it with Algorithm 2 on the same lattice.

## 5. Posids must be unique

Convergence alone doesn't need it. If two chars share a posid, `max` keeps one, and every replica keeps the same one (V5). But the text would be wrong:

- One of two inserted chars would vanish.
- Deleting works by posid, so a reused posid would hide a char nobody deleted. [T] §3.3.2 shows this with site-only disambiguators.

How they stay unique, with the UDIS disambiguators of [T] §3.3.1:

- Every step carries `{counter, {node(), incarnation}}`. The counter goes +1 on every local insert, and `node()` is `doc@<ip>`. The incarnation is random at startup, because the counter isn't saved and starts at 0 again after a restart.
- A posid from the table in PROTOCOL.md ends in a step with a new disambiguator, so it can't exist yet.
- A posid from the §4.1 balancing reuses the disambiguator of whoever created that subtree. Only that same `{node(), incarnation}` fills the subtree, and it checks its own atoms first, so it never takes a slot twice.
- The incarnation is `:rand.uniform(1_000_000_000)` (`@max_encarnacion`). It is random rather than the time because the Pi has no hardware clock: Nerves sets it to the build time at boot (`update_clock: true`) until NTP answers, which may never happen on the hotspot, so two boots could read the same time. 10⁹ < 2³¹, so it fits the 4-byte integer of Erlang's external format, and it travels in every step of every posid.
- The assumption: two sites never share `{node(), incarnation}`. For that to break, two Pis would need the same IP on different networks, then merge later, and also draw the same random number (1 in 10⁹).

Test: the δ-mutator test above also checks that no posid repeats across 3 replicas, with runs of typing that use the balancing.

## 6. A new posid lands strictly between its neighbours

`p < f` are the neighbours in the full order, and `d` is the new disambiguator.

| case | new posid | why `p < new < f` |
|---|---|---|
| empty document | `[{1, d}]` | nothing to compare |
| `p == :inicio` | `f ++ [{0, d}]` | a prefix followed by bit 0 sorts before the prefix |
| `f == :fin` | `p ++ [{1, d}]` | a prefix followed by bit 1 sorts after the prefix |
| `p` is a prefix of `f` | `f ++ [{0, d}]` | below `f` by the same rule. `p < f` means `f` continues `p` with bit 1, and the new posid shares that step, so it is above `p` |
| otherwise | `p ++ [{1, d}]` | above `p`. If `f` is a prefix of `p`, `p` continues `f` with bit 0. If not, `p` and `f` split at some step where `p` is smaller. Either way the new posid shares that step, so it is below `f` |

The balancing (`posid_para/4`) only takes a slot after checking `menor?(p, slot)` and `menor?(slot, f)` explicitly. If either check fails, it falls back to the table.

## 7. Balancing (§4.1) without touching the wire format

Receivers only sort with `menor?`, so how a node builds its paths is invisible on the wire.

**How it works** (`Treedoc.posid_para/4`). When a replica keeps typing right after the last char it inserted itself (`doc.ultimo`), the new char doesn't hang as the right child of the previous one. The tree grows `niveles(h) = ceil(log2(h)) + 1` levels at once (`h` is the length of `p`), and the char takes the smallest slot of that new subtree. The next chars of the run fill its empty slots in infix order. Every step of the subtree carries the disambiguator of the char that created it, and only that site fills it (§5). A lone insert uses the table of §6, because growing several levels for one char would only make paths longer.

**Before.** Typing at the end made the path one step longer per char. `n` chars meant paths of length `n` and a full state of size O(n²).

**After, measured on 2000 chars appended:** the longest path went from 2000 to 108 steps, and the full state from 33 MB to 2.2 MB. Random inserts didn't change (12.7 steps on average).

**What's still linear:**
- Typing backwards, always at the same spot, still adds one step per char.
- `flatten` ([T] §4.2) would fix it, but it needs a distributed commit, so we don't do it.
- Tombstones are never collected.

## 8. The document survives if every node goes down

[A] §2 and [S] §2 assume a replica recovers "with its memory intact". `CpdDoc.Disco` covers that:

- Every 5 s, if the content changed, the replica writes `atomos` and `borrados` to `/data/cpd_doc/documento.bin` on the Pi. It writes a `.tmp` file and renames it, so a power cut never leaves half a file.
- On startup it loads the file with `Protocolo.leer`, the same check as a received message, and joins it into the empty state. A missing or corrupt file gives the empty state.
- An old file is harmless. It is a state below the current one in the lattice, and whatever it lacks arrives from the other nodes.
- `contador` and the incarnation are not saved. The replica starts with a new incarnation, as before, so a file that missed the last inserts can't make it reuse a posid (§5).

On a laptop it only saves if `CPD_DOC_ARCHIVO` is set.

Test: `test/disco_test.exs`.
