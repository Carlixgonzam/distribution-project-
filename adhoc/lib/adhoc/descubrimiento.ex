defmodule Adhoc.Descubrimiento do
  use GenServer

  alias Adhoc.Instancia

  def start_link(_) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def estado() do
    GenServer.call(__MODULE__, :estado)
  end

  def init(:ok) do
    Mdns.EventManager.register()
    send(self(), :revisar)

    {:ok,
     %{
       dominio: Application.get_env(:adhoc, :dominio),
       servicio: Application.get_env(:adhoc, :servicio),
       barrido: Application.get_env(:adhoc, :barrido),
       red: nil,
       servidor: nil,
       cliente: nil,
       anunciado: nil
     }}
  end

  def handle_call(:estado, _de, estado) do
    {:reply, estado, estado}
  end

  def handle_info(:revisar, estado) do
    Process.send_after(self(), :revisar, 10_000)
    {:noreply, trabajar(estado)}
  end

  def handle_info(:otra_vez, estado) do
    {:noreply, trabajar(estado)}
  end

  def handle_info({:red, ip, prefijo}, estado) do
    {:noreply, trabajar(%{estado | red: %{ip: ip, prefijo: prefijo}})}
  end

  def handle_info({_namespace, %Mdns.Client.Device{services: servicios}}, estado) do
    nodos = Instancia.a_conectar(servicios, estado.dominio, estado.servicio, node(), Node.list())

    for nodo <- nodos do
      conectar(nodo)
    end

    {:noreply, estado}
  end

  def handle_info(_otro, estado) do
    {:noreply, estado}
  end

  defp trabajar(estado) do
    estado = asegurar_anuncio(asegurar_cliente(estado))
    buscar(estado)
    estado
  end

  defp asegurar_cliente(estado) do
    pid = Process.whereis(Mdns.Client)

    cond do
      not Node.alive?() or pid == nil or pid == estado.cliente ->
        estado

      iniciar(fn -> Mdns.Client.start() end) == :ok ->
        %{estado | cliente: pid}

      true ->
        estado
    end
  end

  defp asegurar_anuncio(estado) do
    pid = Process.whereis(Mdns.Server)

    cond do
      not Node.alive?() or pid == nil ->
        estado

      pid == estado.servidor and estado.anunciado == node() ->
        estado

      pid == estado.servidor ->
        IO.puts("el nodo cambió de nombre, reiniciando el anuncio mDNS")
        GenServer.stop(Mdns.Server)
        Process.send_after(self(), :otra_vez, 500)
        %{estado | servidor: nil, anunciado: nil}

      iniciar(fn -> Mdns.Server.start() end) == :ok ->
        Mdns.Server.add_service(%Mdns.Server.Service{
          domain: estado.servicio,
          data: Instancia.nombre(estado.dominio, node(), estado.servicio),
          ttl: 120,
          type: :ptr
        })

        IO.puts("anunciando #{inspect(node())} en #{estado.servicio}, dominio #{estado.dominio}")
        %{estado | servidor: pid, anunciado: node()}

      true ->
        estado
    end
  end

  defp buscar(estado) do
    if estado.cliente != nil and estado.cliente == Process.whereis(Mdns.Client) do
      Mdns.Client.query(estado.servicio)
    end

    if estado.barrido and estado.red != nil do
      for ip <- Instancia.vecinos(estado.red.ip, estado.red.prefijo) do
        conectar(String.to_atom(estado.dominio <> "@" <> ip))
      end
    end

    :ok
  end

  defp conectar(nodo) do
    spawn(fn ->
      if Node.connect(nodo) == true do
        IO.puts("conectado a #{inspect(nodo)}")
      end
    end)
  end

  defp iniciar(funcion) do
    try do
      funcion.()
    catch
      :exit, razon -> {:error, razon}
    end
  end
end
