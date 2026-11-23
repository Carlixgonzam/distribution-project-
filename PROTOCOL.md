# Shared document protocol, v1 (draft)

What every group has to match so all nodes edit one document. Anything not listed here is up to each group.

## Network

- Everyone joins the same iPhone hotspot (WPA2). Name and password are shared privately, not in any repo.
- Whoever lends the hotspot: turn on "Maximize Compatibility" and keep the Personal Hotspot screen open while devices join.
- The hotspot hands out `172.20.10.2` to `172.20.10.14`, so 13 devices at most, and iOS may allow fewer. Every Pi and every laptop counts. Let's agree beforehand who joins.
- Node name: `doc@<ipv4>`, e.g. `doc@172.20.10.3`. Long names only (`--name`, never `--sname`).
- Cookie: `cpd2026`.
- Connecting to any one node is enough, Erlang connects you to the rest. Our Pis also try `Node.connect` on every hotspot address every 10 s.
- From a laptop: `iex --name doc@<your ip> --cookie cpd2026 --erl "-kernel prevent_overlapping_partitions false" -S mix`, then `Node.connect(:"doc@<ip of any node>")`.
- Recommended: start every node with `-kernel prevent_overlapping_partitions false`. With the OTP default (`true`), when one link drops `global` also cuts the node's other connections and it stays alone until something reconnects it. Nothing here uses global names, so there is nothing to protect.

## Process

Each node registers a process as `:cpd_doc`. It must accept plain messages (`send/2`). Accepting `GenServer.cast/2` as well is recommended.

## Message

One message for both deltas and full states:

```elixir
{:cpd, 1, node(), {:estado, atoms, tombstones}}

atoms       :: [{posid, char}]
tombstones  :: [posid]
posid       :: [{bit, {counter, {node, incarnation}}}]   # non-empty
bit         :: 0 | 1
counter     :: integer, +1 on every local insert
node        :: atom, node() of the writer
incarnation :: integer, random at startup, e.g. :rand.uniform(1_000_000_000)
char        :: binary, exactly one grapheme when you send it
```

Sending:

- After every local insert or delete, send only that change.
- On `{:nodeup, _}` and every 30 s, send your whole state.
- Send to `{:cpd_doc, n}` for every `n` in `Node.list()`.
- Deleting never removes an atom. Its posid goes into the tombstones.

Receiving. These rules have to be identical on every node, otherwise documents drift apart:

1. Accept the message only if it has exactly the shape above: proper lists, `bit` is 0 or 1, `counter` and `incarnation` are integers, `node` is an atom, `char` is a binary, and every posid is non-empty.
2. Anything else, drop the whole message. No partial merges, and never crash.
3. Don't check `char` beyond `is_binary`. If one group rejected a character that the others keep, the documents would differ.
4. Merge = union of atoms + union of tombstones.
5. If the same posid shows up with two different chars, in one message or across messages, keep `max(a, b)` (Erlang term order).

## Order

The text is the atoms whose posid is not a tombstone, sorted with this function:

```elixir
def menor?([], []), do: false
def menor?([], [{bit, _} | _]), do: bit == 1
def menor?([{bit, _} | _], []), do: bit == 0
def menor?([x | r1], [x | r2]), do: menor?(r1, r2)
def menor?([x | _], [y | _]), do: x < y
```

This is the infix order of section 3.1 of the Treedoc paper. A posid is a path from a virtual root, and each step is `{bit, disambiguator}`: 0 goes left, 1 goes right. Steps with the same bit are mini-nodes of one major node, ordered by `{counter, {node, incarnation}}`, counter first. The five clauses are the paper's three cases:

- `id1` is a prefix of `id2` and `id2` continues with bit 1: `id1 < id2` (clause 2).
- `id2` is a prefix of `id1` and `id1` continues with bit 0: `id1 < id2` (clause 3).
- otherwise compare the first step where they differ (clause 5). With equal bits, the disambiguator decides.

One difference with the paper: we put a disambiguator on every step, not only where it is needed, so every step names one mini-node. The order is still total and dense, and comparing is a plain list walk. V6 and V7 below are Figures 3 and 4 of the paper written this way.

## Deleting

- Deleting adds the posid to the tombstones. The atom stays, because the next new posid is computed from the full order, tombstones included.
- Tombstones are never removed and a deleted character never comes back.
- A tombstone counts even if its atom hasn't arrived yet (V4). Deleting twice is the same as deleting once.

## New posids

`p` and `f` are the neighbours of the new character in the full order, tombstones included. `:inicio` and `:fin` stand for the edges, and `dis = {counter + 1, {node(), incarnation}}`.

| case | new posid |
|---|---|
| empty document | `[{1, dis}]` |
| `p == :inicio` | `f ++ [{0, dis}]` |
| `f == :fin` | `p ++ [{1, dis}]` |
| `p` is a prefix of `f` | `f ++ [{0, dis}]` |
| otherwise | `p ++ [{1, dis}]` |

Any rule works as long as the new posid sorts strictly between `p` and `f` and is never reused. When a node keeps typing right after its own last character, we use the balancing from section 4.1 of the Treedoc paper: the tree grows `ceil(log2(length(p))) + 1` levels at once, and the next characters fill the empty slots of that subtree in infix order. If you do the same, only fill slots whose steps carry your own `{node, incarnation}`.

## Test vectors

Feed each one as a single message into an empty document. The text has to match.

```elixir
# V1, in-order walk
atoms = [
  {[{1, {1, {:a, 1}}}], "c"},
  {[{1, {1, {:a, 1}}}, {0, {2, {:a, 1}}}], "b"},
  {[{1, {1, {:a, 1}}}, {1, {3, {:a, 1}}}], "d"},
  {[{1, {1, {:a, 1}}}, {0, {2, {:a, 1}}}, {0, {4, {:a, 1}}}], "a"}
]
tombstones = []
# => "abcd"

# V2, siblings with the same bit: counter first, then node. A subtree stays with its parent.
atoms = [
  {[{1, {2, {:a, 1}}}], "Z"},
  {[{1, {1, {:b, 1}}}], "Y"},
  {[{1, {1, {:a, 1}}}, {1, {5, {:a, 1}}}], "x"},
  {[{1, {1, {:a, 1}}}], "X"}
]
tombstones = []
# => "XxYZ"

# V3, V1 with "b" deleted
tombstones = [[{1, {1, {:a, 1}}}, {0, {2, {:a, 1}}}]]
# => "acd"

# V4, a tombstone that arrives before its atom still hides it
atoms = []
tombstones = [[{1, {9, {:a, 1}}}]]
# => "", and after receiving {[{1, {9, {:a, 1}}}], "q"} it is still ""

# V5, same posid with two chars
atoms = [{[{1, {1, {:a, 1}}}], "x"}, {[{1, {1, {:a, 1}}}], "y"}]
tombstones = []
# => "y"

# V6, Figure 3 of the paper: W and Y inserted at the same time between c and d
c = [{1, {1, {:c, 1}}}]
b = c ++ [{0, {1, {:b, 1}}}]
e = c ++ [{1, {1, {:e, 1}}}]
d = e ++ [{0, {1, {:d, 1}}}]
w = d ++ [{0, {1, {:w, 1}}}]
y = d ++ [{0, {1, {:y, 1}}}]
atoms = [
  {c, "c"}, {b, "b"}, {b ++ [{0, {1, {:a, 1}}}], "a"},
  {e, "e"}, {d, "d"}, {e ++ [{1, {1, {:f, 1}}}], "f"},
  {w, "W"}, {y, "Y"}, {y ++ [{1, {1, {:z, 1}}}], "Z"}
]
tombstones = []
# => "abcWYZdef"

# V7, Figure 4: V6 plus X between the mini-siblings W and Y
atoms = [{w ++ [{1, {1, {:x, 1}}}], "X"} | atoms]
# => "abcWXYZdef"
```

Our implementation passes all seven in `documento/test/protocolo_test.exs`. Why this converges is in [documento/CRDT.md](documento/CRDT.md).

## Still open

- 30 s for the full-state resend, or longer if the hotspot gets slow?
- Discovery by mDNS and the API exchange belong to the other assignment, see [adhoc/PROTOCOL.md](adhoc/PROTOCOL.md).
