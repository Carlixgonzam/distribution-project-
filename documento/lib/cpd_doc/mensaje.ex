defmodule CpdDoc.Mensaje do
  @nombre Crdt.Replica
  @max_pasos 10_000
  @max_vc 10_000
  @max_bytes_caracter 64

  def nombre() do
    @nombre
  end

  def leer(%{op: :ins, from: from, vc: vc, pos: pos, ch: ch}) do
    if base?(from, vc, pos) and caracter?(ch) do
      {:ok, %{op: :ins, from: from, vc: vc, pos: pos, ch: ch}}
    else
      :error
    end
  end

  def leer(%{op: :del, from: from, vc: vc, pos: pos}) do
    if base?(from, vc, pos) do
      {:ok, %{op: :del, from: from, vc: vc, pos: pos}}
    else
      :error
    end
  end

  def leer(_) do
    :error
  end

  def caracter?(ch) when is_binary(ch) and byte_size(ch) <= @max_bytes_caracter do
    String.valid?(ch) and length(String.graphemes(ch)) == 1
  end

  def caracter?(_) do
    false
  end

  defp base?(from, vc, pos) do
    nodo?(from) and vc?(vc) and propio?(Map.get(vc, from)) and pasos?(pos, 0)
  end

  defp nodo?(from) do
    is_atom(from) and from not in [nil, true, false]
  end

  defp vc?(vc) when is_map(vc) and map_size(vc) <= @max_vc do
    Enum.all?(vc, fn {k, n} -> is_atom(k) and is_integer(n) and n >= 0 end)
  end

  defp vc?(_) do
    false
  end

  defp propio?(n) when is_integer(n) and n >= 1 do
    true
  end

  defp propio?(_) do
    false
  end

  defp pasos?([], n) do
    n > 0
  end

  defp pasos?([{bit, seq, nodo} | resto], n)
       when bit in [0, 1] and is_integer(seq) and seq >= 1 and is_atom(nodo) and n < @max_pasos do
    pasos?(resto, n + 1)
  end

  defp pasos?(_, _) do
    false
  end
end
