# documento

Shared text document. Every node keeps a full copy as an op-based Treedoc CRDT, applies the others' operations in causal order and broadcasts its own. No central server. It speaks the class contract, so it edits the same document as the other groups ([PROTOCOL.md](../PROTOCOL.md)). Why it converges: [CRDT.md](CRDT.md). Run everything below from this folder.

## Editing (IEx on a laptop, or `ssh` to a Pi)

```elixir
CpdDoc.insertar(0, "Hola mundo")    # at a visible index
CpdDoc.borrar(4, 6)                 # 6 chars from index 4
CpdDoc.texto()
CpdDoc.estado()                     # node, neighbours, clock, waiting operations
CpdDoc.conectar("nombre@192.168.1.23")
CpdDoc.salir()                      # offline: neither sends nor receives, the node stays connected
CpdDoc.unirse()                     # back: sends its history, asks for the others', merges by clock
```

## Offline edits without disconnecting the node (for the demo)

`CpdDoc.salir()` puts the replica offline. The Erlang node stays connected (`vecinos` still lists the others), but the replica:

- drops every `{:remote, op}` that arrives (counted in `descartadas`) and answers no `{:hello, _}` or `:nodeup`,
- keeps editing locally: each edit goes to the log as always, but nothing is broadcast.

`CpdDoc.unirse()` sends its whole history to every node and `{:hello, node()}`, so every node sends back its own. The vector clocks do the rest (CRDT.md §3): what a node already has is dropped as a duplicate, what is missing is applied in causal order, and the offline edits are concurrent with the others' and commute. The offline state is kept in `<log>.fuera`, so a node that restarts while offline stays offline until `CpdDoc.unirse()`.

```elixir
# on c
CpdDoc.salir()
CpdDoc.insertar(0, "C ")            # only on c
# on a and b, edits that c doesn't see
CpdDoc.ver()                        # on c: FUERA DE LÍNEA, descartadas > 0
# on c
CpdDoc.unirse()                     # a few ms later all three have the same text
```

## Seeing a node's state (for the demo)

```elixir
CpdDoc.ver()        # panel: node, neighbours, clock, counters, text, raw document, last 10 operations
CpdDoc.raw()        # only the raw part of the panel
CpdDoc.mirar()      # redraws the panel every second for 60 s, to leave it on the TV
CpdDoc.mirar(300)   # the same, for 300 s
```

What each part of the panel is:

- `vecinos`: the nodes this one is connected to right now.
- `reloj`: the vector clock, how many operations of each author this node has applied.
- `FUERA DE LÍNEA`: shown only after `CpdDoc.salir()`, with how many remote operations were dropped.
- `espera`: operations received but waiting for one they depend on (should go back to 0). `recibidas` are the ones applied from the network, `duplicadas` the ones that arrived again and were dropped (normal: every node forwards what it applies, so a node's own operations come back to it), `ignoradas` messages that don't follow the contract.
- `texto`: the whole document as the user sees it, with its line breaks, after `│`.
- `raw`: the Treedoc itself, in the in-order walk: each char with its PosID, a path of `bit·seq·node` steps from the root (bit 0 left, 1 right), and the tombstones marked `borrado`. A path longer than 4 steps shows only its last 2.
- `últimas operaciones`: who did what, as `author #seq`.

On the Pi it works the same over `ssh`, or with the Pi on the classroom TV by HDMI and a USB keyboard.

## Laptop

```sh
mix deps.get
MIX_TARGET=host mix test
MIX_TARGET=host iex --name <name>@<your ip> --cookie cpd2026 \
  --erl "-kernel inet_dist_listen_min 4218 inet_dist_listen_max 4228 prevent_overlapping_partitions false" -S mix
```

- Nodes on the same network find each other by multicast within a few seconds. If not, `CpdDoc.conectar("<node>")`.
- The log is `datos/<name>.log`. Never delete it and keep editing under the same name: pick another name instead.
- `CPD_DOC_BARRIDO=on` also asks every address of the /24 for nodes. It is off on laptops so they don't sweep networks that aren't ours.

## Raspberry Pi 4

```sh
export MIX_TARGET=rpi4 HOTSPOT_SSID="..." HOTSPOT_PSK="..."
mix deps.get
mix firmware
mix burn
```

`HOTSPOT_SSID` and `HOTSPOT_PSK` are the name and password of the router's Wi‑Fi. The Pi joins it and starts as `<hostname>-<epoch>@<ip>`. It announces itself by multicast every 2 s and asks every address of its /24 for nodes every 10 s. The log and the epoch live in `/data/cpd_doc`. `ssh nerves-XXXX.local` (its own hostname) opens IEx. SSH only accepts the public keys in `~/.ssh` of whoever built the firmware.
