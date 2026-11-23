# Shared document protocol

All the groups edit one document with the op-based Treedoc contract of the class, written by `fepecas/treedoc` in [docs/INTEGRATION.md](https://github.com/fepecas/treedoc/blob/main/docs/INTEGRATION.md) and its `DESIGN.md` (sections 3 to 6). That document is the reference. This file is the short version of what our nodes do to match it.

## Network

- Everyone joins the Wi‑Fi of the same router. Name and password are shared privately, not in any repo.
- The router has to:
  - use WPA2‑Personal, or WPA2/WPA3 mixed. Our Pis connect with WPA‑PSK, so a WPA3‑only network won't work.
  - have client isolation (AP or guest isolation) off. With it on, devices get an IP but can't reach each other.
  - let multicast through (discovery). If it doesn't, connect by hand with `Node.connect/1`.
- Cookie `cpd2026`, long names (`--name name@IPv4`, never `--sname`, never `.local`).
- Ports: TCP 4369 (epmd), TCP 4218 to 4228 (distribution), UDP 45892 (discovery). Laptops have to allow them in their firewall.
- Start every node with `-kernel prevent_overlapping_partitions false`. With the OTP default, when one link drops `global` also cuts the node's other links. Nothing here uses global names.
- Keep `net_ticktime` at the OTP default, 60 s, on every node: don't pass it to `Node.start/2` or `:net_kernel.start/2`, and don't set `-kernel net_ticktime`. Erlang doesn't agree on it between nodes. A node with 10 s expects a sign of life every few seconds, while one with 60 s only sends one every 15 s when idle, so after 10 s without edits the first one drops the second. We saw it between nodes with 10 and nodes with 60.

## Node names

- Our Pis: `<hostname>-<epoch>@<IPv4>`, e.g. `nerves-1a2b-3f9c07@192.168.1.23`. The epoch is 6 random hex chars kept in `/data` next to the operation log, so a Pi whose SD card is burned again comes back with a new name and never reuses a sequence number.
- Laptops: any `<name>@<IPv4>`, as long as no other machine ever uses the same name. The log is `datos/<name>.log`; deleting it and editing under the same name again would reuse sequence numbers.

## Process and messages

A process registered as `Crdt.Replica` receives `GenServer.cast/2`:

```elixir
{:remote, %{op: :ins, from: node, vc: %{node => n}, pos: [{bit, seq, node}], ch: "a"}}
{:remote, %{op: :del, from: node, vc: %{node => n}, pos: [{bit, seq, node}]}}
{:hello, node}   # "send me your whole history again"
```

- `vc[from]` is the number of the operation on its node: 1, 2, 3… with no gaps and no reuse. `vc[k]` for any other `k` is how many operations of `k` the origin had applied.
- `pos` is a path from the root. Bit 0 is left, 1 is right, and `{seq, node}` is the disambiguator. The last step carries the `{seq, from}` of the operation.
- `ch` is exactly one grapheme.
- A malformed message is ignored. It never crashes our replica.

## Order

The text is the in-order walk of the tree: left subtree, the char, right subtree, with steps of the same bit ordered by `{seq, node}`:

```elixir
def menor?([], []), do: false
def menor?([], [{bit, _, _} | _]), do: bit == 1
def menor?([{bit, _, _} | _], []), do: bit == 0
def menor?([x | r1], [x | r2]), do: menor?(r1, r2)
def menor?([x | _], [y | _]), do: x < y
```

Deleted chars stay as tombstones.

## Delivery

- After every local edit, one `{:remote, op}` per char to every node in `Node.list()`. Nothing is sent before the operation is on disk (`fsync`).
- An operation from `i` with clock `m` is a duplicate if `m[i] <= vc[i]`, is applied if `m[i] == vc[i] + 1` and `m[k] <= vc[k]` for every other `k`, and waits otherwise. After each one applied, the waiting ones are checked again.
- Every operation applied from the network is forwarded once, unchanged, to every node.
- The whole history, in applied order, is sent again on `:nodeup`, on `{:hello, node}`, and when the replica starts with nodes already connected. On start the replica also sends `{:hello, node()}`.

## Discovery

Every 2 s, one UDP packet `crdt-treedoc-1 <node name>` to `233.252.1.32:45892`, TTL 1. On hearing one of another node not yet connected, `Node.connect/1`. Our Pis also ask epmd on every address of their /24 which nodes it runs, every 10 s. Connecting to any one node is enough: Erlang connects you to the rest.

Our implementation, tests and why it converges: [documento/](documento/).
