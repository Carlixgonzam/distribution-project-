defmodule CpdDoc.Protocolo do
  def mensaje(doc) do
    {:cpd, 1, node(), {:estado, Map.to_list(doc.atomos), MapSet.to_list(doc.borrados)}}
  end

  def difundir(doc) do
    mensaje = mensaje(doc)

    for n <- Node.list() do
      send({:cpd_doc, n}, mensaje)
    end

    :ok
  end

  def leer({:cpd, 1, origen, {:estado, atomos, borrados}}) when is_atom(origen) do
    if atomos?(atomos) and posids?(borrados) do
      {:ok, %{atomos: Map.new(atomos), borrados: MapSet.new(borrados)}}
    else
      :error
    end
  end

  def leer(_) do
    :error
  end

  defp atomos?([]) do
    true
  end

  defp atomos?([{posid, caracter} | resto]) when is_binary(caracter) do
    posid?(posid) and atomos?(resto)
  end

  defp atomos?(_) do
    false
  end

  defp posids?([]) do
    true
  end

  defp posids?([posid | resto]) do
    posid?(posid) and posids?(resto)
  end

  defp posids?(_) do
    false
  end

  defp posid?([]) do
    false
  end

  defp posid?(posid) do
    pasos?(posid)
  end

  defp pasos?([]) do
    true
  end

  defp pasos?([{bit, {contador, {nodo, encarnacion}}} | resto])
       when bit in [0, 1] and is_integer(contador) and is_atom(nodo) and is_integer(encarnacion) do
    pasos?(resto)
  end

  defp pasos?(_) do
    false
  end
end
