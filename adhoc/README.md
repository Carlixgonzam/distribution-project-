# adhoc

Multi-tenant ad hoc network. Nodes announce themselves over mDNS, connect only to nodes of their own domain, and ask each other for their API. The format is in [PROTOCOL.md](PROTOCOL.md). Run everything below from this folder.

## Laptop

```sh
mix deps.get
MIX_TARGET=host mix test
MIX_TARGET=host iex --name a@127.0.0.1 --cookie cpd2026 -S mix
OPERACIONES=eco,hora MIX_TARGET=host iex --name b@127.0.0.1 --cookie cpd2026 -S mix
DOMINIO=otro MIX_TARGET=host iex --name c@127.0.0.1 --cookie otra -S mix
```

After a few seconds `a` and `b` show up in each other's `Node.list()`, and `c` stays alone. `Adhoc.Descubrimiento.estado()` shows what a node is announcing.

Then, from `a`:

```elixir
Adhoc.Api.apis()
Adhoc.Api.llamar(:"b@127.0.0.1", :eco, ["hola"])
Adhoc.Api.llamar(:"b@127.0.0.1", :nombre, [])   # {:error, :no_existe}, b doesn't publish it
```

`OPERACIONES` picks what a laptop node publishes (default `eco,hora,nombre`).

## Raspberry Pi 4

```sh
export MIX_TARGET=rpi4 HOTSPOT_SSID="..." HOTSPOT_PSK="..."
mix deps.get
mix firmware
mix burn
```

The Pi starts as `doc@<ip>` once it joins the hotspot, then announces itself. If the hotspot drops multicast, set `barrido: true` in `config/config.exs` to also try every address of the subnet.
