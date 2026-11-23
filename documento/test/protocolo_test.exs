defmodule CpdDoc.ProtocoloTest do
  use ExUnit.Case, async: false

  alias CpdDoc.Protocolo
  alias CpdDoc.Replica
  alias CpdDoc.Treedoc

  test "un estado enviado y leído llega igual" do
    {doc, _} = Treedoc.insertar(Treedoc.nuevo(), 0, "a", {:a, 1})
    {doc, _} = Treedoc.insertar(doc, 1, "b", {:a, 1})
    {doc, _} = Treedoc.borrar(doc, 0)

    {:ok, leido} = Protocolo.leer(Protocolo.mensaje(doc))
    assert leido.atomos == doc.atomos
    assert leido.borrados == doc.borrados
  end

  test "vectores de prueba de PROTOCOL.md" do
    a = fn c -> {c, {:a, 1}} end

    v1 = [
      {[{1, a.(1)}], "c"},
      {[{1, a.(1)}, {0, a.(2)}], "b"},
      {[{1, a.(1)}, {1, a.(3)}], "d"},
      {[{1, a.(1)}, {0, a.(2)}, {0, a.(4)}], "a"}
    ]

    v2 = [
      {[{1, a.(2)}], "Z"},
      {[{1, {1, {:b, 1}}}], "Y"},
      {[{1, a.(1)}, {1, a.(5)}], "x"},
      {[{1, a.(1)}], "X"}
    ]

    assert texto(v1, []) == "abcd"
    assert texto(v2, []) == "XxYZ"
    assert texto(v1, [[{1, a.(1)}, {0, a.(2)}]]) == "acd"
    assert texto([], [[{1, a.(9)}]]) == ""
    assert texto([{[{1, a.(9)}], "q"}], [[{1, a.(9)}]]) == ""
    assert texto([{[{1, a.(1)}], "x"}, {[{1, a.(1)}], "y"}], []) == "y"
    assert texto(figura_3(), []) == "abcWYZdef"
    assert texto(figura_4(), []) == "abcWXYZdef"
  end

  defp figura_3() do
    c = [{1, {1, {:c, 1}}}]
    b = c ++ [{0, {1, {:b, 1}}}]
    e = c ++ [{1, {1, {:e, 1}}}]
    d = e ++ [{0, {1, {:d, 1}}}]
    w = d ++ [{0, {1, {:w, 1}}}]
    y = d ++ [{0, {1, {:y, 1}}}]

    [
      {c, "c"},
      {b, "b"},
      {b ++ [{0, {1, {:a, 1}}}], "a"},
      {e, "e"},
      {d, "d"},
      {e ++ [{1, {1, {:f, 1}}}], "f"},
      {w, "W"},
      {y, "Y"},
      {y ++ [{1, {1, {:z, 1}}}], "Z"}
    ]
  end

  defp figura_4() do
    {w, "W"} = Enum.find(figura_3(), fn {_posid, caracter} -> caracter == "W" end)
    [{w ++ [{1, {1, {:x, 1}}}], "X"} | figura_3()]
  end

  defp texto(atomos, borrados) do
    {:ok, delta} = Protocolo.leer({:cpd, 1, :t, {:estado, atomos, borrados}})
    Treedoc.texto(Treedoc.merge(Treedoc.nuevo(), delta))
  end

  test "un PosID repetido dentro del mismo mensaje no depende del orden" do
    paso = {1, {1, {:a, 1}}}
    {:ok, d1} = Protocolo.leer({:cpd, 1, :a, {:estado, [{[paso], "x"}, {[paso], "y"}], []}})
    {:ok, d2} = Protocolo.leer({:cpd, 1, :a, {:estado, [{[paso], "y"}, {[paso], "x"}], []}})

    assert d1.atomos == %{[paso] => "y"}
    assert d2.atomos == %{[paso] => "y"}
  end

  test "formas y versiones desconocidas se rechazan" do
    paso = {1, {1, {:a, 1}}}

    assert Protocolo.leer({:cpd, 2, :a, {:estado, [], []}}) == :error
    assert Protocolo.leer({:cpd, 1, :a, {:otro, [], []}}) == :error
    assert Protocolo.leer({:cpd, 1, :a, {:estado, [{[paso], 97}], []}}) == :error
    assert Protocolo.leer({:cpd, 1, :a, {:estado, [{[{2, {1, {:a, 1}}}], "x"}], []}}) == :error
    assert Protocolo.leer({:cpd, 1, :a, {:estado, [{[], "x"}], []}}) == :error
    assert Protocolo.leer({:cpd, 1, :a, {:estado, [], [[paso] | :impropia]}}) == :error
    assert Protocolo.leer(:basura) == :error
    assert {:ok, _} = Protocolo.leer({:cpd, 1, :a, {:estado, [{[paso], "x"}], [[paso]]}})
  end

  test "la réplica :cpd_doc edita, recibe deltas e ignora mensajes raros sin caerse" do
    pid = Process.whereis(:cpd_doc)

    assert Replica.insertar(0, "h") == :ok
    assert Replica.insertar(1, "i") == :ok
    assert Replica.borrar(9) == {:error, :posicion_invalida}

    send(:cpd_doc, :basura)
    send(:cpd_doc, {:cpd, 99, :otro, :lo_que_sea})
    send(:cpd_doc, {:cpd, 1, :otro, {:estado, [{[{1, {1, {:a, 1}}} | :mal], "z"}], []}})
    GenServer.cast(:cpd_doc, {:cpd, 1, :otro@pc, {:estado, [{[{1, {1, {:otro, 7}}}], "!"}], []}})

    texto = Replica.texto()
    assert Process.whereis(:cpd_doc) == pid
    assert Enum.sort(String.graphemes(texto)) == ["!", "h", "i"]
  end
end
