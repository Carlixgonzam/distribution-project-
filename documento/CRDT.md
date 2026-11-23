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
- Every line carries a CRC32 of the operation. A changed byte that still decodes into a valid operation (another char, another sequence number) fails the check and counts as damaged, instead of being loaded silently.
- A damaged line in the middle keeps the valid prefix, moves the file aside and, on the Pi, deletes the epoch, so the node comes back with a new name. Skipping the line would leave a hole in the clock.
- On the Pi the name is `<hostname>-<epoch>@<ip>`. Burning the SD card again deletes `/data`, log and epoch together, so the Pi comes back with a new name and starts numbering from 1 under it.

Tests: "reinicio: la réplica vuelve desde su log, se pone al día y sigue numerando" in `cluster_test.exs`, and `historial_test.exs`.

## 5. A new PosID lands strictly between its neighbours

`p` is the visible char left of the cursor (or the root `[]`), `f` the next char after `p` in the full order, tombstones included (or `nil`), `d` the new `{seq, node}`:

| case | new PosID | why `p < new < f` |
|---|---|---|
| `f` is in the subtree of `p` (`p` is a prefix of `f`) | `f ++ [{0, d}]` | left child of `f`: before `f`, and still in the subtree of `p` on the side of `f` |
| otherwise | `p ++ [{1, d}]` | right child of `p`: after `p`, and the subtree of `p` ends before `f` |

A text inserted in one call (a paste) is placed as a balanced subtree: the middle char goes between `p` and `f` by the table, the left half in its left subtree and the right half in its right subtree, recursively. A new subtree is empty and lies between `p` and `f`, so every char still lands there, in text order, and the depth grows by about log₂ n instead of n. The chars are numbered in text order, and each PosID ends in its own `{seq, node}`, as the contract asks. A child can arrive before its parent: the document is a map of paths, so that is fine (and the other groups' implementations accept it too, tested with `fepecas`).

Without balancing, pasting 5000 chars made a 5000-step path, and sorting the document took 34 s, longer than any call waits. With it, 20 ms.

Test: "insertar texto y borrar rangos coinciden con un String en 500 ediciones".

## 6. Interleaving

[A] §9.2 says Treedoc can interleave two words typed at the same place at the same time ("Hello Al Ciharcliee!"). With this rule each word hangs from its own first char, and a subtree stays together in the in-order walk, so they don't interleave, typing forwards or backwards.

Tests: "sin intercalado: Alice y Charlie…" in `treedoc_test.exs`, and "escrituras simultáneas en la misma posición…" with real nodes.

## 7. Network

- **Discovery** (`CpdDoc.Descubrimiento`): the multicast announcement of the contract every 2 s, and on the Pi a sweep of its /24 every 10 s that asks each address's epmd which nodes it runs. Connecting to one node is enough: Erlang connects the rest.
- **`prevent_overlapping_partitions false`.** With the OTP default, when one link drops, `global` also cuts the node's other links. We saw it with 3 nodes: when `c` dropped, `a` lost `b` too. We use no global names, so that isolation buys nothing.

Where the discovery values come from. The first five are the contract (`INTEGRATION.md` of `fepecas/treedoc`, level L2): changing them means we no longer find the other groups, and they no longer find us. The rest can be tuned.

| value | what it is | source |
|---|---|---|
| `@grupo {233, 252, 1, 32}` | multicast address of the announcement | contract |
| `@puerto 45_892` | UDP port of the announcement | contract |
| `@etiqueta "crdt-treedoc-1 "` | text every announcement starts with | contract |
| `@anunciar_cada 2_000` | one announcement every 2 s | contract |
| first announcement at start (`send(self(), :anunciar)` in `init`) | | contract ("every 2 s, starting at once") |
| `@barrer_cada 10_000` | one sweep of the /24 every 10 s | our first version: `Defi` already swept every 10 s |
| first sweep 1 s after start | `send_after(:barrer, 1_000)` | our choice, so the first one doesn't wait 10 s |
| `@reintentar 30_000` | wait before trying again an announced node that didn't answer | taken from `andresmosqueraw/treedoc-op-nerves` (`@retry`); avoids trying an unreachable node every 2 s |
| `@max_nombres 256` | most announced names turned into atoms | taken from the same repo (`@max_seen`); a flood of names can't use up the atom table (§8) |
| `@nombre` (the regex) | a valid name: up to 64 letters, digits, `_`, `-` or `.`, then `@` and an IPv4 | taken from the same repo (`@name_re`); `fepecas` only checks the tag |
| 64 addresses at a time, 3 s per epmd query, 5 s per address | pace of the sweep | our choice (that repo uses 64 and 15 s) |
| sweep off on laptops (`CPD_DOC_BARRIDO`) | | our choice, so a laptop doesn't sweep a network that isn't ours |

## 8. What can't bring a node down

Everything that comes from outside is checked, and every process answers anything it doesn't expect instead of crashing:

| input or event | what happens | test |
|---|---|---|
| any term as `cast`, `send` or `call` to `Crdt.Replica` | ignored, counted in `estado().ignoradas`; an unknown call answers `{:error, :desconocida}` | `replica_test.exs`, 1500 random terms from another node in `cluster_test.exs` |
| an operation of the right shape but too big (a `ch` of megabytes, 10 000+ steps, 10 000+ clock entries) | rejected before it is walked | `mensaje_test.exs`, 20 000 random inputs |
| operations out of order, repeated, or waiting for one that never comes | wait in a buffer of at most 50 000; duplicates dropped | `causal_test.exs`, 1000 random histories |
| a log cut at any byte, or with any byte changed | truncated, or the valid prefix kept and the file moved aside | `historial_test.exs` |
| a log that can't be opened | the replica doesn't start, calls answer `{:error, :sin_replica}` | `replica_test.exs` |
| the replica killed | the supervisor starts it again from its log and it catches up | `cluster_test.exs` |
| the network lost (`Node.stop`) and back | edits go on under the last name and are sent on reconnect | `cluster_test.exs` |
| garbage UDP packets, a flood of announced names | ignored; at most 256 names become atoms | `descubrimiento_test.exs` |
| a /31 or /32 network | no sweep, instead of invalid addresses | `descubrimiento_test.exs` |
| `/data` not writable on the Pi | the epoch lives in memory: a new name each boot, never a reused number | |
| a call that takes long | the IEx helpers wait 30 s and answer `{:error, :tiempo_agotado}` | |

## 9. Why op-based

The first version of this project was state-based (delta-state, Almeida, Shoker, Baquero 2018), in the history of this repository. Both are valid. [A] Table 2 compares them:

| | op-based (now) | delta-state (before) |
|---|---|---|
| delivery | exactly once, causal | any: lost, duplicated, reordered |
| participants | known group | open |
| messages | one small operation each | full state now and then |
| durable state | the log is required (§4) | optional |

We moved to op-based so all the groups of the class edit one document with the same contract.

## 10. Limitations

- **Tombstones and history grow for ever.** Removing them needs causal stability or a distributed commit ([T] §4.2, [A] §4.2), and needs every participant known. Fine for a demo.
- **The whole history is sent again on every `:nodeup`,** to every neighbour. With a few thousand operations it is fine.
- **Typing char by char at the end still makes the path one step longer per char.** Pastes are balanced (§5), but the §4.1 balancing of [T] for separate keystrokes reuses disambiguators, and the contract asks the last step to carry the operation's own one. Hundreds of typed chars are fine; thousands typed in one place slow the document down.
- **The clock gets one entry per node name.** A Pi that changes IP has a new name, so a new entry.
- **Deleting a laptop's log and editing under the same name** reuses sequence numbers. Use another name.
