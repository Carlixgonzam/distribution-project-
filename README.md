# Documento distribuido con Treedoc (ISIS 4218)

Documento de texto colaborativo entre Raspberry Pi 4, sin servidor central, en Elixir con Nerves.
Cada nodo guarda el documento completo como un CRDT (Treedoc) y difunde sus cambios a `Node.list()`.

## Estructura

- `lib/cpd_doc/treedoc.ex`: el CRDT (orden de PosIDs, insertar, borrar, merge).
- `lib/cpd_doc/protocolo.ex`: el mensaje común con los otros grupos, `{:cpd, 1, node(), {:estado, atomos, borrados}}`.
- `lib/cpd_doc/replica.ex`: el GenServer `:cpd_doc` (API `insertar/2`, `borrar/1`, `texto/0`).
- `lib/cpd_doc/red.ex`: en la Pi, arranca el nodo `doc@IP` cuando `wlan0` recibe IP.
- `lib/proyectodistribu/defi.ex`: avisos de conexión y desconexión de nodos.
- `config/target.exs`: Wi-Fi del hotspot y SSH.

## Tests en el computador

```sh
mix deps.get
MIX_TARGET=host mix test
```

## Dos nodos en el mismo computador

```sh
MIX_TARGET=host iex --sname a --cookie cpd2026 -S mix    # terminal 1
MIX_TARGET=host iex --sname b --cookie cpd2026 -S mix    # terminal 2
```

En `b`: `Node.connect(:"a@NOMBRE_DEL_COMPU")`, y luego `CpdDoc.Replica.insertar(0, "h")` y `CpdDoc.Replica.texto()` en ambos.

## Firmware para la Pi 4

Las credenciales del hotspot no están en el repo: se leen al compilar.

```sh
export MIX_TARGET=rpi4
export HOTSPOT_SSID="..."
export HOTSPOT_PSK="..."
mix deps.get
mix firmware
mix burn        # borra toda la microSD
```

El firmware solo acepta SSH con las llaves públicas de `~/.ssh` de quien lo compila.
