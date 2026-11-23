defmodule CpdDoc.Descubrimiento do
  use GenServer

  def start_link(_) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def descubrir(ip, prefijo) do
    for vecino <- vecinos(ip, prefijo) do
      spawn(fn -> Node.connect(String.to_atom("doc@" <> vecino)) end)
    end

    :ok
  end

  def vecinos(ip, prefijo) do
    [a, b, c, d] = Enum.map(String.split(ip, "."), fn x -> String.to_integer(x) end)

    if prefijo < 24 do
      []
    else
      tamano = Integer.pow(2, 32 - prefijo)
      base = d - rem(d, tamano)

      for x <- (base + 1)..(base + tamano - 2), x != d do
        Enum.join([a, b, c, x], ".")
      end
    end
  end

  def init(:ok) do
    :net_kernel.monitor_nodes(true)
    {:ok, %{}}
  end

  def handle_info({:nodeup, nodo}, estado) do
    IO.puts("se conecto #{inspect(nodo)}")
    {:noreply, estado}
  end

  def handle_info({:nodedown, nodo}, estado) do
    IO.puts("se desconecto #{inspect(nodo)}")
    {:noreply, estado}
  end
end
