# documento

Shared text document. Every Raspberry Pi keeps a full copy of the document as a Treedoc CRDT and broadcasts its edits to all connected nodes. No central server.

The message format we use with the other groups is in [PROTOCOL.md](../PROTOCOL.md), and why it converges is in [CRDT.md](CRDT.md). Run everything below from this folder.

## Laptop

```sh
mix deps.get
MIX_TARGET=host mix test
MIX_TARGET=host iex --name a@127.0.0.1 --cookie cpd2026 --erl "-kernel prevent_overlapping_partitions false" -S mix
```

Start a second node with `--name b@127.0.0.1`, run `Node.connect(:"a@127.0.0.1")`, then edit with `CpdDoc.Replica.insertar(0, "h")`, `CpdDoc.Replica.borrar(0)` and `CpdDoc.Replica.texto()`. Add `CPD_DOC_ARCHIVO=/some/file.bin` before the command to keep the document across restarts.

## Raspberry Pi 4

```sh
export MIX_TARGET=rpi4 HOTSPOT_SSID="..." HOTSPOT_PSK="..."
mix deps.get
mix firmware
mix burn
```

The Pi joins the hotspot, starts as `doc@<ip>` and tries to connect to every address on the hotspot subnet every 10 s. The document is saved to `/data` every 5 s, so it survives reboots. SSH only accepts the public keys in `~/.ssh` of whoever built the firmware.
