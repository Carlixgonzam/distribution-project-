defmodule CpdDoc.Red do
  use GenServer

  def start_link(_) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def init(:ok) do
    VintageNet.subscribe(["interface", "wlan0", "addresses"])
    send(self(), :revisar)
    {:ok, %{ip: nil}}
  end

  def handle_info(:revisar, estado) do
    direcciones = VintageNet.get(["interface", "wlan0", "addresses"], [])
    {:noreply, actualizar(ipv4(direcciones), estado)}
  end

  def handle_info({VintageNet, _propiedad, _viejo, nuevo, _meta}, estado) do
    {:noreply, actualizar(ipv4(nuevo), estado)}
  end

  defp actualizar(ip, estado) do
    if ip == estado.ip and Node.alive?() do
      estado
    else
      detener_nodo()
      arrancar_nodo(ip)
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
    %{ip: nil}
  end

  defp arrancar_nodo(ip) do
    System.cmd("epmd", ["-daemon"])
    nombre = String.to_atom("doc@" <> ip)

    case Node.start(nombre, name_domain: :longnames) do
      {:ok, _} ->
        Node.set_cookie(:cpd2026)
        IO.puts("nodo arrancado: #{inspect(Node.self())}")
        %{ip: ip}

      {:error, razon} ->
        IO.puts("no se pudo arrancar #{inspect(nombre)}: #{inspect(razon)}, reintento en 5 s")
        Process.send_after(self(), :revisar, 5000)
        %{ip: nil}
    end
  end

  defp ipv4(nil) do
    nil
  end

  defp ipv4(direcciones) do
    case Enum.find(direcciones, fn d -> d.family == :inet end) do
      nil -> nil
      d -> Enum.join(Tuple.to_list(d.address), ".")
    end
  end
end
