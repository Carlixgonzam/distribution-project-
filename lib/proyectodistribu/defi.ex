defmodule Proyectodistribu.Defi do
  use GenServer
  def start_link(_) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end
  def conectar(nodo) do
    Node.connect(nodo)
  end
  def broadcast(mensaje) do
    GenServer.cast(__MODULE__, {:broadcast, mensaje})
  end
  def init(:ok) do
    :net_kernel.monitor_nodes(true)
    {:ok, %{}}
  end
  def handle_cast({:broadcast, mensaje}, estado) do
    for nodo <- Node.list() do
      send({__MODULE__, nodo}, {:remoto, Node.self(), mensaje})
    end
    {:noreply, estado}
  end
  def handle_info({:remoto, origen, mensaje}, estado) do
    IO.puts("[#{inspect(origen)}] #{inspect(mensaje)}")
    {:noreply, estado}
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
