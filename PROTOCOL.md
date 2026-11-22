# Shared document protocol, v1 (draft)

What every group has to match so all nodes edit one document. Anything not listed here is up to each group.

## Network

- Everyone joins the same iPhone hotspot (WPA2). Name and password are shared privately, not in any repo.
- Whoever lends the hotspot: turn on "Maximize Compatibility" and keep the Personal Hotspot screen open while devices join.
- The hotspot hands out `172.20.10.2` to `172.20.10.14`, so 13 devices at most, and iOS may allow fewer. Every Pi and every laptop counts. Let's agree beforehand who joins.
- Node name: `doc@<ipv4>`, e.g. `doc@172.20.10.3`. Long names only (`--name`, never `--sname`).
- Cookie: `cpd2026`.
- Connecting to any one node is enough, Erlang connects you to the rest. Our Pis also try `Node.connect` on every hotspot address every 10 s.
- From a laptop: `iex --name doc@<your ip> --cookie cpd2026 -S mix`, then `Node.connect(:"doc@<ip of any node>")`.

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

This is an in-order walk of a binary tree where every step carries a disambiguator. Children with the same bit are ordered by `{counter, {node, incarnation}}`, counter first.

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
```

## Still open

- 30 s for the full-state resend, or longer if the hotspot gets slow?
- Discovery by mDNS and the API exchange belong to the other assignment (ad hoc). We'll send a separate proposal for those.
