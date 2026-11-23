# Why the document converges

The document is Treedoc [T] as an operation-based CRDT (CmRDT, [S] §2.4), with causal delivery, following the class contract ([PROTOCOL.md](../PROTOCOL.md)). Each claim points to the test that checks it.

- [T] Preguiça, Marquès, Shapiro, Leția. A commutative replicated data type for cooperative editing. ICDCS 2009.
- [S] Shapiro, Preguiça, Baquero, Zawirski. Conflict-free Replicated Data Types. INRIA RR-7687, 2011.
- [A] Almeida. Approaches to Conflict-free Replicated Data Types. ACM Computing Surveys, 2024.

## 1. The theorem we rely on

[S] Theorem 2.2: an op-based object is SEC (replicas that delivered the same updates have the same state) if updates are delivered exactly once, in causal order, and concurrent updates commute. §2 shows they commute, §3 how delivery is exactly-once and causal, §4 why sequence numbers never repeat, which delivery depends on.

The code follows the prepare/effect split of [S] §2.4 and [A] §3.1:

| | where | what |
|---|---|---|
| prepare | `Treedoc.preparar_insercion/5`, `preparar_borrado/3`, only on the node that edits | reads the state, picks the PosID |
| effect | `Treedoc.aplicar/2`, on every node | adds the char, or the tombstone |

## 2. Concurrent operations commute

The argument of [T] §2.2:

- Two inserts never share a PosID, because the last step carries the `{seq, node}` of the operation (§4). They add different keys to the map, in any order.
- A delete only adds its PosID to the tombstones. Two deletes of the same PosID give the same set in any order.
- A delete and the insert of the same PosID are never concurrent: whoever deleted the char saw it, so the insert happened before. Causal delivery (§3) applies the insert first everywhere.

The text only depends on the set of chars and tombstones, sorted with `menor?`, the in-order walk of [T] §3.1.

Tests: "3 réplicas con entrega causal en órdenes aleatorios convergen (200 ejecuciones)" in `treedoc_test.exs`, and Figures 3 and 4 of [T] in the same file.

## 3. Exactly once and in causal order

`CpdDoc.Causal` is the rule of the contract, the vector clocks of causal broadcast:

- A duplicate (`m[i] <= vc[i]`) is dropped, so an operation that arrives twice is applied once.
- An operation is applied only after everything its clock says it depends on. Otherwise it waits, and is applied as soon as what was missing arrives.

Messages can be lost when a link drops, so delivery is made reliable:

- Every operation applied from the network is forwarded once. If the origin reached only one node before going down, the others still get it.
- On `:nodeup` and on `{:hello, node}`, every node sends its whole history again. A node that was cut off, or that restarted, catches up.

Erlang keeps the order of messages between two nodes, so waiting only shows up with three or more nodes: an operation forwarded by one path arrives before its dependency from the origin, or a reconnection replays histories.

Tests: `causal_test.exs` (every permutation of a causal history ends the same), and in `cluster_test.exs`, with real nodes: forwarding in a chain A‑B‑C, a partition that heals, a late node.

## 4. Sequence numbers never repeat

If a node numbered two operations the same, the others would drop the second as a duplicate and the documents would differ for ever. So:

- Every local edit is written to the log with one `fsync` before anything is applied or sent (`CpdDoc.Historial`). On restart the log rebuilds the document and the clock, and numbering goes on where it was.
- A cut last line (power failure) is truncated: that operation never left the node.
- A damaged line in the middle keeps the valid prefix, moves the file aside and, on the Pi, deletes the epoch, so the node comes back with a new name. Skipping the line would leave a hole in the clock.
- On the Pi the name is `<hostname>-<epoch>@<ip>`. Burning the SD card again deletes `/data`, log and epoch together, so the Pi comes back with a new name and starts numbering from 1 under it.

Tests: "reinicio: la réplica vuelve desde su log, se pone al día y sigue numerando" in `cluster_test.exs`, and `historial_test.exs`.

## 5. A new PosID lands strictly between its neighbours

`p` is the visible char left of the cursor (or the root `[]`), `f` the next char after `p` in the full order, tombstones included (or `nil`), `d` the new `{seq, node}`:

| case | new PosID | why `p < new < f` |
|---|---|---|
| `f` is in the subtree of `p` (`p` is a prefix of `f`) | `f ++ [{0, d}]` | left child of `f`: before `f`, and still in the subtree of `p` on the side of `f` |
| otherwise | `p ++ [{1, d}]` | right child of `p`: after `p`, and the subtree of `p` ends before `f` |

A text inserted in one call is placed one char after the other, on the state left by the previous one. The last step always carries the operation's own `{seq, node}`, as the contract asks.

Test: "insertar texto y borrar rangos coinciden con un String en 500 ediciones".

## 6. Interleaving

[A] §9.2 says Treedoc can interleave two words typed at the same place at the same time ("Hello Al Ciharcliee!"). With this rule each word hangs from its own first char, and a subtree stays together in the in-order walk, so they don't interleave, typing forwards or backwards.

Tests: "sin intercalado: Alice y Charlie…" in `treedoc_test.exs`, and "escrituras simultáneas en la misma posición…" with real nodes.

## 7. Network

- **Discovery** (`CpdDoc.Descubrimiento`): the multicast announcement of the contract every 2 s, and on the Pi a sweep of its /24 every 10 s that asks each address's epmd which nodes it runs. Connecting to one node is enough: Erlang connects the rest.
- **`prevent_overlapping_partitions false`.** With the OTP default, when one link drops, `global` also cuts the node's other links. We saw it with 3 nodes: when `c` dropped, `a` lost `b` too. We use no global names, so that isolation buys nothing.

## 8. Why op-based

The first version of this project was state-based (delta-state, Almeida, Shoker, Baquero 2018), in the history of this repository. Both are valid. [A] Table 2 compares them:

| | op-based (now) | delta-state (before) |
|---|---|---|
| delivery | exactly once, causal | any: lost, duplicated, reordered |
| participants | known group | open |
| messages | one small operation each | full state now and then |
| durable state | the log is required (§4) | optional |

We moved to op-based so all the groups of the class edit one document with the same contract.

## 9. Limitations

- **Tombstones and history grow for ever.** Removing them needs causal stability or a distributed commit ([T] §4.2, [A] §4.2), and needs every participant known. Fine for a demo.
- **The whole history is sent again on every `:nodeup`,** to every neighbour. With a few thousand operations it is fine.
- **Typing at the end makes the path one step longer per char.** The §4.1 balancing of [T] reuses disambiguators, and the contract asks the last step to carry the operation's own one.
- **The clock gets one entry per node name.** A Pi that changes IP has a new name, so a new entry.
- **Deleting a laptop's log and editing under the same name** reuses sequence numbers. Use another name.
