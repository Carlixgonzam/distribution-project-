defmodule CpdDoc.Treedoc do
  def vacio() do
    %{atomos: %{}, borrados: MapSet.new()}
  end

  def nuevo() do
    Map.merge(vacio(), %{contador: 0, ultimo: nil})
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

  def posid_para(doc, p, f, dis) do
    {_, sitio} = dis

    if p == :inicio or p != doc.ultimo or (f != :fin and prefijo?(p, f)) do
      nuevo_posid(p, f, dis)
    else
      hueco = siguiente_hueco(p, sitio)

      if hueco != nil and not Map.has_key?(doc.atomos, hueco) and menor?(p, hueco) and
           (f == :fin or menor?(hueco, f)) do
        hueco
      else
        crecer(p, dis)
      end
    end
  end

  def niveles(h) do
    if h <= 1 do
      1
    else
      techo_log2(h, 0) + 1
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
        posid = posid_para(doc, p, f, {contador, sitio})
        delta = %{vacio() | atomos: %{posid => caracter}}
        {%{merge(doc, delta) | contador: contador, ultimo: posid}, delta}
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
      | atomos: Map.merge(a.atomos, b.atomos, fn _posid, x, y -> max(x, y) end),
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

  defp crecer(p, dis) do
    p ++ [{1, dis}] ++ List.duplicate({0, dis}, niveles(length(p)) - 1)
  end

  defp siguiente_hueco(p, sitio) do
    {_, d} = List.last(p)
    {_, dueno} = d
    {prefijo, propio} = Enum.split_while(p, fn {_, x} -> x != d end)

    case propio do
      [{1, _} | rel] ->
        if dueno == sitio and Enum.all?(rel, fn {_, x} -> x == d end) do
          sucesor(prefijo ++ [{1, d}], rel, d, niveles(length(prefijo)))
        else
          nil
        end

      _ ->
        nil
    end
  end

  defp sucesor(raiz, rel, d, k) do
    if length(rel) < k - 1 do
      raiz ++ rel ++ [{1, d}] ++ List.duplicate({0, d}, k - 2 - length(rel))
    else
      case Enum.drop_while(Enum.reverse(rel), fn {bit, _} -> bit == 1 end) do
        [] -> nil
        [_ | resto] -> raiz ++ Enum.reverse(resto)
      end
    end
  end

  defp techo_log2(h, k) do
    if Integer.pow(2, k) >= h do
      k
    else
      techo_log2(h, k + 1)
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
