defmodule Adhoc.Mensaje do
  def pregunta(dominio, nodo, operaciones) do
    {:adhoc, 1, :api?, dominio, nodo, operaciones}
  end

  def respuesta(dominio, nodo, operaciones) do
    {:adhoc, 1, :api, dominio, nodo, operaciones}
  end

  def llamada(dominio, pid, nombre, argumentos) do
    {:adhoc, 1, :llamar, dominio, pid, nombre, argumentos}
  end

  def resultado(dominio, nodo, respuesta) do
    {:adhoc, 1, :resultado, dominio, nodo, respuesta}
  end

  def difundir(mensaje) do
    for nodo <- Node.list() do
      send({:adhoc_api, nodo}, mensaje)
    end

    :ok
  end

  def leer({:adhoc, 1, :api?, dominio, nodo, operaciones}) do
    if is_binary(dominio) and is_atom(nodo) and operaciones?(operaciones) do
      {:api?, dominio, nodo, operaciones}
    else
      :error
    end
  end

  def leer({:adhoc, 1, :api, dominio, nodo, operaciones}) do
    if is_binary(dominio) and is_atom(nodo) and operaciones?(operaciones) do
      {:api, dominio, nodo, operaciones}
    else
      :error
    end
  end

  def leer({:adhoc, 1, :llamar, dominio, pid, nombre, argumentos}) do
    if is_binary(dominio) and is_pid(pid) and is_atom(nombre) and lista?(argumentos) do
      {:llamar, dominio, pid, nombre, argumentos}
    else
      :error
    end
  end

  def leer({:adhoc, 1, :resultado, dominio, nodo, respuesta}) do
    if is_binary(dominio) and is_atom(nodo) and respuesta?(respuesta) do
      {:resultado, dominio, nodo, respuesta}
    else
      :error
    end
  end

  def leer(_otro) do
    :error
  end

  defp operaciones?([]) do
    true
  end

  defp operaciones?([{nombre, aridad, texto} | resto]) do
    is_atom(nombre) and is_integer(aridad) and aridad >= 0 and is_binary(texto) and
      operaciones?(resto)
  end

  defp operaciones?(_otro) do
    false
  end

  defp lista?([]) do
    true
  end

  defp lista?([_primero | resto]) do
    lista?(resto)
  end

  defp lista?(_otro) do
    false
  end

  defp respuesta?({:ok, _valor}) do
    true
  end

  defp respuesta?({:error, _razon}) do
    true
  end

  defp respuesta?(_otro) do
    false
  end
end
