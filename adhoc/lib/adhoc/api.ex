defmodule Adhoc.Api do
  use GenServer

  alias Adhoc.Mensaje
  alias Adhoc.Operaciones

  def start_link(_) do
    GenServer.start_link(__MODULE__, :ok, name: :adhoc_api)
  end

  def apis() do
    GenServer.call(:adhoc_api, :apis)
  end

  def preguntar() do
    send(:adhoc_api, :preguntar)
    :ok
  end

  def llamar(nodo, nombre, argumentos, espera \\ 5000) do
    case GenServer.call(:adhoc_api, {:buscar, nodo, nombre, length(argumentos)}) do
      {:ok, dominio} -> pedir(dominio, nodo, nombre, argumentos, espera)
      error -> error
    end
  end

  def init(:ok) do
    :net_kernel.monitor_nodes(true)
    send(self(), :revisar)

    {:ok,
     %{
       dominio: Application.get_env(:adhoc, :dominio),
       propias: Operaciones.describir(Application.get_env(:adhoc, :operaciones, [])),
       apis: %{}
     }}
  end

  def handle_call(:apis, _de, estado) do
    {:reply, estado.apis, estado}
  end

  def handle_call({:buscar, nodo, nombre, aridad}, _de, estado) do
    operaciones =
      if nodo == node() do
        estado.propias
      else
        Map.get(estado.apis, nodo)
      end

    respuesta =
      cond do
        operaciones == nil ->
          {:error, :sin_api}

        Enum.any?(operaciones, fn {n, a, _texto} -> n == nombre and a == aridad end) ->
          {:ok, estado.dominio}

        true ->
          {:error, :no_existe}
      end

    {:reply, respuesta, estado}
  end

  def handle_info({:nodeup, _nodo}, estado) do
    preguntar(estado)
    {:noreply, estado}
  end

  def handle_info({:nodedown, nodo}, estado) do
    if Map.has_key?(estado.apis, nodo) do
      IO.puts("#{inspect(nodo)} se fue, olvido su API")
    end

    {:noreply, %{estado | apis: Map.delete(estado.apis, nodo)}}
  end

  def handle_info(:revisar, estado) do
    Process.send_after(self(), :revisar, 10_000)

    if Node.list() -- Map.keys(estado.apis) != [] do
      preguntar(estado)
    end

    {:noreply, estado}
  end

  def handle_info(:preguntar, estado) do
    preguntar(estado)
    {:noreply, estado}
  end

  def handle_info(mensaje, estado) do
    {:noreply, recibir(Mensaje.leer(mensaje), estado)}
  end

  defp recibir({:api?, dominio, nodo, operaciones}, estado) do
    if dominio == estado.dominio do
      Mensaje.difundir(Mensaje.respuesta(dominio, node(), estado.propias))
      guardar(estado, nodo, operaciones)
    else
      estado
    end
  end

  defp recibir({:api, dominio, nodo, operaciones}, estado) do
    if dominio == estado.dominio do
      guardar(estado, nodo, operaciones)
    else
      estado
    end
  end

  defp recibir({:llamar, dominio, pid, nombre, argumentos}, estado) do
    if dominio == estado.dominio do
      propias = estado.propias

      spawn(fn ->
        respuesta = Operaciones.ejecutar(propias, nombre, argumentos)
        send(pid, Mensaje.resultado(dominio, node(), respuesta))
      end)
    end

    estado
  end

  defp recibir(_otro, estado) do
    estado
  end

  defp guardar(estado, nodo, operaciones) do
    cond do
      nodo not in Node.list() ->
        estado

      Map.get(estado.apis, nodo) == operaciones ->
        estado

      true ->
        IO.puts("API de #{inspect(nodo)}: #{texto(operaciones)}")
        %{estado | apis: Map.put(estado.apis, nodo, operaciones)}
    end
  end

  defp preguntar(estado) do
    Mensaje.difundir(Mensaje.pregunta(estado.dominio, node(), estado.propias))
  end

  defp pedir(dominio, nodo, nombre, argumentos, espera) do
    yo = self()

    spawn(fn ->
      send({:adhoc_api, nodo}, Mensaje.llamada(dominio, self(), nombre, argumentos))

      receive do
        mensaje -> send(yo, {:respuesta_api, leer_resultado(mensaje, dominio, nodo)})
      after
        espera -> send(yo, {:respuesta_api, {:error, :timeout}})
      end
    end)

    receive do
      {:respuesta_api, respuesta} -> respuesta
    end
  end

  defp leer_resultado(mensaje, dominio, nodo) do
    case Mensaje.leer(mensaje) do
      {:resultado, d, n, respuesta} ->
        if d == dominio and n == nodo do
          respuesta
        else
          {:error, :respuesta_invalida}
        end

      _otro ->
        {:error, :respuesta_invalida}
    end
  end

  defp texto(operaciones) do
    Enum.map_join(operaciones, ", ", fn {nombre, aridad, _texto} -> "#{nombre}/#{aridad}" end)
  end
end
