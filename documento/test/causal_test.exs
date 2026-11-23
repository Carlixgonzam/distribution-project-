defmodule CpdDoc.CausalTest do
  use ExUnit.Case, async: true

  alias CpdDoc.Causal

  defp op(from, vc) do
    %{op: :del, from: from, vc: vc, pos: [{1, 1, from}]}
  end

  test "la siguiente operación local suma 1 a la entrada propia" do
    assert Causal.siguiente(%{}, :a) == {1, %{a: 1}}
    assert Causal.siguiente(%{a: 3, b: 2}, :a) == {4, %{a: 4, b: 2}}
  end

  test "duplicada, entregable o en espera" do
    vc = %{a: 2, b: 1}

    assert Causal.clasificar(vc, op(:a, %{a: 2})) == :duplicada
    assert Causal.clasificar(vc, op(:a, %{a: 3, b: 1})) == :entregable
    assert Causal.clasificar(vc, op(:a, %{a: 4})) == :espera
    assert Causal.clasificar(vc, op(:a, %{a: 3, b: 2})) == :espera
    assert Causal.clasificar(vc, op(:c, %{c: 1, a: 2})) == :entregable
  end

  test "lo que espera se aplica en cadena cuando llega lo que faltaba" do
    a1 = op(:a, %{a: 1})
    a2 = op(:a, %{a: 2})
    b1 = op(:b, %{a: 2, b: 1})

    {vc, espera, [], :espera} = Causal.recibir(%{}, [], b1)
    {vc, espera, [], :espera} = Causal.recibir(vc, espera, a2)
    {vc, espera, [], :espera} = Causal.recibir(vc, espera, a2)
    assert length(espera) == 2
    assert Causal.faltan(vc, b1) == %{a: 2}

    {vc, espera, aplicadas, :aplicada} = Causal.recibir(vc, espera, a1)
    assert aplicadas == [a1, a2, b1]
    assert espera == []
    assert vc == %{a: 2, b: 1}
    assert {^vc, [], [], :duplicada} = Causal.recibir(vc, [], a2)
  end

  test "todas las permutaciones de una historia causal dan el mismo reloj y respetan la causalidad" do
    a1 = op(:a, %{a: 1})
    b1 = op(:b, %{a: 1, b: 1})
    a2 = op(:a, %{a: 2, b: 1})
    c1 = op(:c, %{c: 1})
    b2 = op(:b, %{a: 2, b: 2, c: 1})
    historia = [a1, b1, a2, c1, b2]

    for orden <- permutaciones(historia) do
      {vc, espera, aplicadas} = recibir_todas(orden)

      assert vc == %{a: 2, b: 2, c: 1}
      assert espera == []
      assert Enum.sort(aplicadas) == Enum.sort(historia)
      assert antes?(aplicadas, a1, b1)
      assert antes?(aplicadas, b1, a2)
      assert antes?(aplicadas, a2, b2)
      assert antes?(aplicadas, c1, b2)
    end
  end

  defp recibir_todas(orden) do
    Enum.reduce(orden, {%{}, [], []}, fn o, {vc, espera, aplicadas} ->
      {vc, espera, nuevas, _} = Causal.recibir(vc, espera, o)
      {vc, espera, aplicadas ++ nuevas}
    end)
  end

  defp antes?(lista, x, y) do
    Enum.find_index(lista, fn o -> o == x end) < Enum.find_index(lista, fn o -> o == y end)
  end

  defp permutaciones([]) do
    [[]]
  end

  defp permutaciones(lista) do
    for x <- lista, resto <- permutaciones(lista -- [x]) do
      [x | resto]
    end
  end
end
