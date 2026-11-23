defmodule CpdDoc do
  alias CpdDoc.Mensaje
  alias CpdDoc.Vista

  def insertar(i, texto) do
    llamar({:local, {:insertar, i, texto}})
  end

  def borrar(i) do
    borrar(i, 1)
  end

  def borrar(i, n) do
    llamar({:local, {:borrar, i, n}})
  end

  def texto() do
    llamar(:texto)
  end

  def estado() do
    llamar(:estado)
  end

  def historial() do
    llamar(:historial)
  end

  def documento() do
    llamar(:documento)
  end

  def ver() do
    Vista.ver()
  end

  def raw() do
    Vista.raw()
  end

  def mirar() do
    mirar(60)
  end

  def mirar(segundos) do
    Vista.mirar(segundos)
  end

  def conectar(nodo) when is_atom(nodo) do
    Node.connect(nodo)
  end

  def conectar(nodo) when is_binary(nodo) do
    Node.connect(String.to_atom(nodo))
  end

  def conectar(_nodo) do
    {:error, :nodo_invalido}
  end

  defp llamar(mensaje) do
    GenServer.call(Mensaje.nombre(), mensaje, 30_000)
  catch
    :exit, {:timeout, _} -> {:error, :tiempo_agotado}
    :exit, _ -> {:error, :sin_replica}
  end
end
