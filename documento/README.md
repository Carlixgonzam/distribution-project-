# documento

Shared text document. Every node keeps a full copy as an op-based Treedoc CRDT, applies the others' operations in causal order and broadcasts its own. No central server. It speaks the class contract, so it edits the same document as the other groups ([PROTOCOL.md](../PROTOCOL.md)). Why it converges: [CRDT.md](CRDT.md). Run everything below from this folder.

## Editing (IEx on a laptop, or `ssh` to a Pi)

```elixir
CpdDoc.insertar(0, "Hola mundo")    # at a visible index
CpdDoc.borrar(4, 6)                 # 6 chars from index 4
CpdDoc.texto()
CpdDoc.estado()                     # node, neighbours, clock, waiting operations
CpdDoc.conectar("nombre@192.168.1.23")
```

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
