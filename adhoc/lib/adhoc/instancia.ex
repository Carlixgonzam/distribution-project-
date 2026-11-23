defmodule Adhoc.Instancia do
  def nombre(dominio, nodo, servicio) do
    dominio <> "." <> Atom.to_string(nodo) <> "." <> servicio
  end

  def leer(texto, servicio) do
    sufijo = "." <> servicio

    if String.ends_with?(texto, sufijo) do
      separar(String.replace_suffix(texto, sufijo, ""))
    else
      :error
    end
  end

  def a_conectar(servicios, dominio, servicio, yo, conectados) do
    ya = Enum.map([yo | conectados], fn n -> Atom.to_string(n) end)

    servicios
    |> Enum.map(fn s -> leer(s, servicio) end)
    |> Enum.filter(fn r -> mismo_dominio?(r, dominio) end)
    |> Enum.map(fn {:ok, _, nodo} -> nodo end)
    |> Enum.reject(fn nodo -> nodo in ya end)
    |> Enum.uniq()
    |> Enum.map(fn nodo -> String.to_atom(nodo) end)
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

  defp separar(resto) do
    case String.split(resto, ".", parts: 2) do
      [dominio, nodo] -> validar(dominio, nodo)
      _ -> :error
    end
  end

  defp validar(dominio, nodo) do
    case String.split(nodo, "@") do
      [nombre, host] when dominio != "" and nombre != "" and host != "" -> {:ok, dominio, nodo}
      _ -> :error
    end
  end

  defp mismo_dominio?({:ok, dominio, _}, dominio) do
    true
  end

  defp mismo_dominio?(_, _) do
    false
  end
end
