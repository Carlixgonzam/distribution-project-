# distribution-project-

Shared text document for ISIS 4218. Every Raspberry Pi keeps a full copy of the document as a Treedoc CRDT and broadcasts its edits to all connected nodes. No central server.

The message format we use with the other groups is in [PROTOCOL.md](PROTOCOL.md).

## Laptop

```sh
mix deps.get
MIX_TARGET=host mix test
MIX_TARGET=host iex --sname a --cookie cpd2026 -S mix
```

Start a second node with `--sname b`, run `Node.connect(:"a@<hostname>")`, then edit with `CpdDoc.Replica.insertar(0, "h")`, `CpdDoc.Replica.borrar(0)` and `CpdDoc.Replica.texto()`.

## Raspberry Pi 4

```sh
export MIX_TARGET=rpi4 HOTSPOT_SSID="..." HOTSPOT_PSK="..."
mix deps.get
mix firmware
mix burn
```

The Pi joins the hotspot, starts as `doc@<ip>` and tries to connect to every address on the hotspot subnet every 10 s. SSH only accepts the public keys in `~/.ssh` of whoever built the firmware.
