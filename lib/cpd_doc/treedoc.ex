defmodule CpdDoc.Treedoc do
  def vacio() do
    %{atomos: %{}, borrados: MapSet.new()}
  end

  def nuevo() do
    Map.put(vacio(), :contador, 0)
  end

  def menor?([], []) do
    false
  end

  def menor?([], [{bit, _} | _]) do
    bit == 1
  end

  def menor?([{bit, _} | _], []) do
    bit == 0
  end

  def menor?([x | r1], [x | r2]) do
    menor?(r1, r2)
  end

  def menor?([x | _], [y | _]) do
    x < y
  end

  def orden(doc) do
    Enum.sort(Map.to_list(doc.atomos), fn {p1, _}, {p2, _} -> menor?(p1, p2) end)
  end

  def visibles(doc) do
    sin_borrados(orden(doc), doc.borrados)
  end

  def texto(doc) do
    Enum.map_join(visibles(doc), fn {_, caracter} -> caracter end)
  end

  # Limitación: no se implementa el balanceo de la sección 4.1 de Treedoc.
  # Cada PosID nuevo se cuelga como hijo de un vecino, así que al escribir
  # siempre al final cada letra queda como hijo derecho de la anterior y los
  # caminos crecen una posición por letra escrita.
  def nuevo_posid(:inicio, :fin, dis) do
    [{1, dis}]
  end

  def nuevo_posid(:inicio, f, dis) do
    f ++ [{0, dis}]
  end

  def nuevo_posid(p, :fin, dis) do
    p ++ [{1, dis}]
  end

  def nuevo_posid(p, f, dis) do
    if prefijo?(p, f) do
      f ++ [{0, dis}]
    else
      p ++ [{1, dis}]
    end
  end

  def insertar(doc, i, caracter, sitio) do
    orden = orden(doc)
    visibles = sin_borrados(orden, doc.borrados)

    cond do
      not is_integer(i) or i < 0 or i > length(visibles) ->
        {:error, :posicion_invalida}

      not is_binary(caracter) or String.length(caracter) != 1 ->
        {:error, :caracter_invalido}

      true ->
        p = anterior(visibles, i)
        f = siguiente(orden, p)
        contador = doc.contador + 1
        posid = nuevo_posid(p, f, {contador, sitio})
        delta = %{vacio() | atomos: %{posid => caracter}}
        {%{merge(doc, delta) | contador: contador}, delta}
    end
  end

  def borrar(doc, i) do
    visibles = visibles(doc)

    if is_integer(i) and i >= 0 and i < length(visibles) do
      {posid, _} = Enum.at(visibles, i)
      delta = %{vacio() | borrados: MapSet.new([posid])}
      {merge(doc, delta), delta}
    else
      {:error, :posicion_invalida}
    end
  end

  def merge(a, b) do
    %{
      a
      | atomos: Map.merge(a.atomos, b.atomos),
        borrados: MapSet.union(a.borrados, b.borrados)
    }
  end

  defp sin_borrados(orden, borrados) do
    Enum.reject(orden, fn {posid, _} -> MapSet.member?(borrados, posid) end)
  end

  defp anterior(_visibles, 0) do
    :inicio
  end

  defp anterior(visibles, i) do
    {posid, _} = Enum.at(visibles, i - 1)
    posid
  end

  defp siguiente([], :inicio) do
    :fin
  end

  defp siguiente([{f, _} | _], :inicio) do
    f
  end

  defp siguiente(orden, p) do
    case Enum.drop_while(orden, fn {q, _} -> q != p end) do
      [_, {f, _} | _] -> f
      _ -> :fin
    end
  end

  defp prefijo?([], _) do
    true
  end

  defp prefijo?([x | r1], [x | r2]) do
    prefijo?(r1, r2)
  end

  defp prefijo?(_, _) do
    false
  end
end
