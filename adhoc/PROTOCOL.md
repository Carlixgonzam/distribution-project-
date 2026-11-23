# Ad hoc protocol, v1 (draft)

How nodes of one domain find each other on the hotspot. Only the nodes of the same domain connect.

## Discovery (Task 1)

- mDNS, service type `_cpd._tcp.local`. We use the library from the course slides, `mdns` 1.0.13.
- Each node answers PTR queries for `_cpd._tcp.local` with one instance name:

  ```
  <domain>.<node>._cpd._tcp.local
  e.g. doc.doc@172.20.10.3._cpd._tcp.local
  ```

- `<domain>` has no dots, and `<node>` is the full Erlang node name. Node names are `<domain>@<ipv4>`, with long names.
- Every node sends the query `_cpd._tcp.local` at startup, whenever its IP changes, and every 10 s. It connects with `Node.connect/1` to every instance with its own domain that isn't itself and isn't connected yet.
- Each domain has its own cookie. For `doc` it is `cpd2026`. A node from another domain fails the Erlang handshake even if it tries to connect.

Don't put the domain in a TXT record. `mdns` 1.0.13 crashes when a TXT record has more than one entry, and then silently stops announcing.

## API exchange (Task 2)

Every node registers a process as `:adhoc_api`. All messages are tuples tagged `:adhoc` and version `1`, and carry the domain. A node drops any message that is malformed or has another domain, without answering.

```elixir
{:adhoc, 1, :api?, domain, node, operations}        # "here is my API, send me yours"
{:adhoc, 1, :api, domain, node, operations}         # answer
{:adhoc, 1, :llamar, domain, pid, name, args}       # call one operation
{:adhoc, 1, :resultado, domain, node, reply}        # sent to pid
```

- `operations` is a proper list of `{name, arity, description}`: atom, integer >= 0, string. Each node publishes its own list, so two nodes can have different APIs.
- `:api?` and `:api` go by broadcast to `{:adhoc_api, n}` for every `n` in `Node.list()`. A node asks on `:nodeup`, when it starts, and every 10 s while some connected node is missing from its cache. It answers every `:api?` of its own domain.
- A node only keeps the API of nodes in its `Node.list()` and forgets it on `:nodedown`. Repeated `:api?`/`:api` messages just overwrite the cache.
- `:llamar` goes straight to the node that owns the operation. It runs only if that node publishes `name` with `length(args)` as arity, otherwise the reply is `{:error, :no_existe}`.
- `reply` is `{:ok, value}` or `{:error, reason}`. The caller waits 5 s, then gives up with `{:error, :timeout}`. Calls are never retried, so an operation runs at most once.

Our nodes publish `eco/1`, `hora/0` and `nombre/0`; the Pi also publishes `temperatura/0`.
