# Protocol (draft v1)

What every group needs to match so all nodes share one document.

## Network and discovery (Task 1)

- Everyone joins the same iPhone hotspot. The password is shared privately.
- Node name: `doc@<ipv4>`, for example `doc@172.20.10.3`. Long names only (`--name`, not `--sname`).
- Cookie: `cpd2026`.
- Connecting to any one node is enough: Erlang then connects you to the others it knows. Our Pis also try `Node.connect` on every address of the hotspot subnet every 10 s.
- From a laptop: `iex --name doc@<your ip> --cookie cpd2026 -S mix`.

## Process

Each node runs a process registered as `:cpd_doc`. It has to accept plain messages (`send/2`). Accepting `GenServer.cast/2` too is recommended.

## Message

There is only one message, used for both deltas and full states:

```elixir
{:cpd, 1, node(), {:estado, atoms, tombstones}}

atoms      :: [{posid, char}]
tombstones :: [posid]
posid      :: [{bit, {counter, {node, incarnation}}}]   # non-empty list
bit        :: 0 | 1
counter    :: integer, grows with every local insert
node       :: atom, node() of the writer
incarnation:: integer, random at startup (:rand.uniform(1_000_000_000))
char       :: string with exactly one grapheme
```

- Send it to `{:cpd_doc, n}` for every `n` in `Node.list()`.
- After every local insert or delete, send only the change.
- On `{:nodeup, _}` and every 30 s, send the whole state.
- On receive, union the atoms and the tombstones. Messages with an unknown version or shape are ignored, never crash.
- Deleting never removes an atom. Its posid goes into the tombstones.

## Order

The visible text is the atoms whose posids are not tombstones, sorted with this function. It has to be the same on every node.

```elixir
def menor?([], []), do: false
def menor?([], [{bit, _} | _]), do: bit == 1
def menor?([{bit, _} | _], []), do: bit == 0
def menor?([x | r1], [x | r2]), do: menor?(r1, r2)
def menor?([x | _], [y | _]), do: x < y
```

## New posids

`p` and `f` are the neighbours of the new character in the full order (tombstones included). `:inicio` and `:fin` stand for the edges, and `dis = {counter + 1, {node(), incarnation}}`.

| case | new posid |
|---|---|
| empty document | `[{1, dis}]` |
| `p == :inicio` | `f ++ [{0, dis}]` |
| `f == :fin` | `p ++ [{1, dis}]` |
| `p` is a prefix of `f` | `f ++ [{0, dis}]` |
| otherwise | `p ++ [{1, dis}]` |

Only the order and the message format need to match. These rules are just how we make posids, and any rule that puts the new posid between `p` and `f` and never repeats one works too.

When a node keeps typing right after its own last character, we also use the balancing from section 4.1 of the Treedoc paper. The tree grows `ceil(log2(length(p))) + 1` levels at once, and the next characters fill the empty slots of that subtree in infix order. Every step of such a subtree carries the `dis` of the character that created it. If you do the same, only fill slots whose `dis` has your own `{node, incarnation}`, so two nodes never mint the same posid.

## Still open

- `char` limited to one grapheme?
- 30 s for the full-state resend?
