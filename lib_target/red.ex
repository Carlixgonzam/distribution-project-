defmodule CpdDoc.Red do
  use GenServer

  def start_link(_) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def init(:ok) do
    VintageNet.subscribe(["interface", "wlan0", "addresses"])
    send(self(), :revisar)
    Process.send_after(self(), :buscar, 10_000)
    {:ok, %{ip: nil, prefijo: nil}}
  end

  def handle_info(:buscar, estado) do
    if estado.ip != nil and Node.alive?() do
      Proyectodistribu.Defi.descubrir(estado.ip, estado.prefijo)
    end

    Process.send_after(self(), :buscar, 10_000)
    {:noreply, estado}
  end

  def handle_info(:revisar, estado) do
    direcciones = VintageNet.get(["interface", "wlan0", "addresses"], [])
    {:noreply, actualizar(ipv4(direcciones), estado)}
  end

  def handle_info({VintageNet, _propiedad, _viejo, nuevo, _meta}, estado) do
    {:noreply, actualizar(ipv4(nuevo), estado)}
  end

  defp actualizar(red, estado) do
    if red == estado and Node.alive?() do
      estado
    else
      detener_nodo()
      arrancar_nodo(red)
    end
  end

  defp detener_nodo() do
    if Node.alive?() do
      IO.puts("deteniendo nodo #{inspect(Node.self())}")
      Node.stop()
    end
  end

  defp arrancar_nodo(nil) do
    IO.puts("wlan0 sin IPv4, esperando")
    %{ip: nil, prefijo: nil}
  end

  defp arrancar_nodo(red) do
    System.cmd("epmd", ["-daemon"])
    nombre = String.to_atom("doc@" <> red.ip)

    case Node.start(nombre, name_domain: :longnames) do
      {:ok, _} ->
        Node.set_cookie(:cpd2026)
        IO.puts("nodo arrancado: #{inspect(Node.self())}")
        red

      {:error, razon} ->
        IO.puts("no se pudo arrancar #{inspect(nombre)}: #{inspect(razon)}, reintento en 5 s")
        Process.send_after(self(), :revisar, 5000)
        %{ip: nil, prefijo: nil}
    end
  end

  defp ipv4(nil) do
    nil
  end

  defp ipv4(direcciones) do
    case Enum.find(direcciones, fn d -> d.family == :inet end) do
      nil -> nil
      d -> %{ip: Enum.join(Tuple.to_list(d.address), "."), prefijo: d.prefixlen}
    end
  end
end
